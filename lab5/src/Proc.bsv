import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;

typedef struct {
  Instruction inst;
  Addr pc;
  Addr ppc;
  Bool epoch;
} Fetch2Decode deriving(Bits, Eq);

typedef struct {
  DecodedInst dInst;
  Addr pc;
  Addr ppc;
  Bool epoch;
} Decode2Rest deriving(Bits, Eq);

(*synthesize*)
module mkProc(Proc);
  Reg#(Addr)    pc  <- mkRegU;
  RFile         rf  <- mkRFile;
  IMemory     iMem  <- mkIMemory;
  DMemory     dMem  <- mkDMemory;
  CsrFile     csrf <- mkCsrFile;

  Reg#(ProcStatus)   stat		<- mkRegU;
  Fifo#(1,ProcStatus) statRedirect <- mkBypassFifo; // enq < deq

  // Control hazard handling Elements
  Reg#(Bool) fEpoch <- mkRegU;
  Reg#(Bool) eEpoch <- mkRegU;

  Fifo#(1, Addr)         execRedirect <- mkBypassFifo; // enq < deq

  Fifo#(2, Fetch2Decode) f2d <- mkPipelineFifo; // deq < enq

  Fifo#(2, Decode2Rest) d2r <- mkPipelineFifo; // deq < enq

  Bool memReady = iMem.init.done() && dMem.init.done();
  rule test (!memReady);
    let e = tagged InitDone;
    iMem.init.request.put(e);
    dMem.init.request.put(e);
  endrule

  // doFetch used in Execise 1

  // rule doFetch(csrf.started && stat == AOK);
	// /* Exercise_2 */
	// /*TODO: 
	// Remove 1-cycle inefficiency when execRedirect is used. */
  //  	let inst = iMem.req(pc);
  //  	let ppc = pc + 4;

  //   if(execRedirect.notEmpty) begin
  //     execRedirect.deq;
  //     pc <= execRedirect.first;
  //     fEpoch <= !fEpoch;
  //   end
  //   else begin
  //     pc <= ppc;
  //   end

  //   f2d.enq(Fetch2Decode{inst:inst, pc:pc, ppc:ppc, epoch:fEpoch}); 
  //   $display("Fetch : from Pc %d , \n", pc);
  // endrule

	/* Exercise_2 */
	/*TODO: 
	Remove 1-cycle inefficiency when execRedirect is used. */
  rule doFetch(csrf.started && stat == AOK);
    // 다음 PC와 epoch를 여기서 계산해 doRest 이후 나오는 값을 가지고 실행 가능하도록 함 (Bypass 이니 enq가 먼저, deq 나중)
    Addr nextPC   = (execRedirect.notEmpty) ? execRedirect.first : pc;
    Bool nextEpoch = (execRedirect.notEmpty) ? !fEpoch : fEpoch;
    Bool changeEpoch  = execRedirect.notEmpty; 

    let inst = iMem.req(nextPC);                
    let ppc = nextPC + 4;

    // 업데이트된 값으로 f2d로 넘어가고, reg도 그 값으로 변경됨. 
    pc <= ppc;                           
    if (changeEpoch) begin
        execRedirect.deq;
        fEpoch <= nextEpoch;
    end
    f2d.enq(Fetch2Decode{inst: inst, pc: nextPC, ppc: ppc, epoch: nextEpoch});
    $display("Fetch : from Pc %d", nextPC);
  endrule

  rule doDecode(csrf.started && stat == AOK);
    let inst = f2d.first.inst;
    let pc = f2d.first.pc;
    let ppc = f2d.first.ppc;
    let iEpoch = f2d.first.epoch;

    let dInst = decode(inst);
    $display(fshow(dInst));

    f2d.deq;
    d2r.enq(Decode2Rest{dInst: dInst, pc: pc, ppc: ppc, epoch: iEpoch});
  endrule

  rule doRest(csrf.started && stat == AOK);
	/* Exercise_1 */
	/* TODO: 
	Divide the doRest rule into doDecode, doRest rules 
	to implement 3-stage pipelined processor */
    let pc   = d2r.first.pc;
    let ppc    = d2r.first.ppc;
    let iEpoch = d2r.first.epoch;
    let dInst = d2r.first.dInst;
    d2r.deq;

    if(iEpoch == eEpoch) begin
        // Decode 부분은 doDecode rule에서 실행됨

        // Register Read 
        let rVal1 = isValid(dInst.src1) ? rf.rd1(validValue(dInst.src1)) : ?;
        let rVal2 = isValid(dInst.src2) ? rf.rd2(validValue(dInst.src2)) : ?;
        let csrVal = isValid(dInst.csr) ? csrf.rd(validValue(dInst.csr)) : ?;

    		// Execute         
        let eInst = exec(dInst, rVal1, rVal2, pc, ppc, csrVal);       
        $display(fshow(eInst));        
        
        if(eInst.mispredict) begin
          eEpoch <= !eEpoch;
          execRedirect.enq(eInst.addr);
          $display("jump! :mispredicted, address %d ", eInst.addr);
        end

      //Memory 
      let iType = eInst.iType;
      case(iType)
        Ld :
        begin
          let d <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
          eInst.data = d;
        end

        St:
        begin
          let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end
        Unsupported :
        begin
          $fwrite(stderr, "ERROR: Executing unsupported instruction\n");
          $finish;
        end
      endcase

      //WriteBack 
      if (isValid(eInst.dst)) begin
          rf.wr(fromMaybe(?, eInst.dst), eInst.data);
      end
      csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

      
	  /* Exercise_3 */
	  /* TODO:
	  1. count the number of each instruciton type
	    Ctr(Control)   : J, Jr, Br
	    Mem(Memory)    : Ld, St 
	        
	  2. count the number of mispredictions */    
    
    // 1. dInst.iType 를 사용해 counter을 증가
    if (dInst.iType == J || dInst.iType == Jr || dInst.iType == Br) begin
      csrf.incInstTypeCnt(Ctr);
    end
    if (dInst.iType == Ld || dInst.iType == St) begin
      csrf.incInstTypeCnt(Mem);
    end

    // 2. iEpoch랑 eEpoch가 다르면 misprediction.
    let eInst2 = exec(dInst, rVal1, rVal2, pc, ppc, csrVal);  
    if (eInst2.mispredict) begin
      csrf.incBPMissCnt();
    end

	  /* Exercise_4 */
	  /* TODO:
	  1. Implement incInstTypeCnt method in CsrFile.bsv 
	  2. count number of mispredictions for each instruction type */

    if (eInst2.mispredict) begin
      case (dInst.iType)
          J: csrf.incMissInstTypeCnt(Jumpmiss);
          Jr: csrf.incMissInstTypeCnt(JumpRegmiss);
          Br: csrf.incMissInstTypeCnt(Branchmiss);
          default: noAction;
      endcase
    end 
    else begin
        case (dInst.iType)
            J: csrf.incMissInstTypeCnt(Jump);
            Jr: csrf.incMissInstTypeCnt(JumpReg);
            Br: csrf.incMissInstTypeCnt(Branch);
            default: noAction;
        endcase
    end
  end
  endrule

  rule upd_Stat(csrf.started);
	$display("Stat update");
  	statRedirect.deq;
    stat <= statRedirect.first;
  endrule

  method ActionValue#(CpuToHostData) cpuToHost;
    let retV <- csrf.cpuToHost;
    return retV;
  endmethod

  method Action hostToCpu(Bit#(32) startpc) if (!csrf.started && memReady);
    csrf.start(0);
    eEpoch <= False;
    fEpoch <= False;
    pc <= startpc;
    stat <= AOK;
  endmethod

  interface iMemInit = iMem.init;
  interface dMemInit = dMem.init;

endmodule
