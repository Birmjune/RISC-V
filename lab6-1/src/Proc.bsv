import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Scoreboard::*;
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
  Data rVal1;
  Data rVal2;
  Data csrVal;
} Decode2Execute deriving(Bits, Eq);

typedef struct {
  ExecInst eInst;
  Bool flag;
} Execute2Mem deriving(Bits, Eq);

typedef struct {
  ExecInst eInst;
  Bool flag;
} Mem2WriteBack deriving(Bits, Eq);

(*synthesize*)
module mkProc(Proc);
  Reg#(Addr) pc[2] <- mkCRegU(2);
  RFile rf  <- mkBypassRFile;  // Use the BypassRFile to handle the hazards. (wr < rd, Refer to M10.)
  //RFile         rf  <- mkRFile;
  IMemory iMem  <- mkIMemory;
  DMemory dMem  <- mkDMemory;
  CsrFile csrf <- mkCsrFile;
  
  // The control hazard is handled using two Epoch registers and one BypassFifo.
  Reg#(Bool) fEpoch <- mkRegU;
  Reg#(Bool) eEpoch <- mkRegU;
  Fifo#(1, Addr) execRedirect <- mkBypassFifo; 
  
  // PipelineFifo to construct 5-stage pipeline
  Fifo#(1, Fetch2Decode) f2d <- mkPipelineFifo;
  Fifo#(1, Decode2Execute) d2e <- mkPipelineFifo;
  Fifo#(1, Execute2Mem) e2m <- mkPipelineFifo;
  Fifo#(1, Mem2WriteBack) m2w <- mkPipelineFifo;

  // Scoreboard instantiation. Use this module to address the data hazard. 
  // Refer to scoreboard.bsv in the 'common-lib' directory.
  Scoreboard#(4) sb <- mkPipelineScoreboard;


/* Lab 6-1: TODO) - Implement a 5-stage pipelined processor using the provided scoreboard.
                  - Refer to common-lib/scoreboard.bsv and the PowerPoint slides.
                  - Use the scoreboard interface properly. */

  rule doFetch(csrf.started);
    let inst = iMem.req(pc[1]); // pc[1]을 써서 바로 받아옴
    let ppc = pc[1] + 4;

    if (execRedirect.notEmpty) begin
      execRedirect.deq;
      pc[1] <= execRedirect.first;
      // pc <= execRedirect.first;
      fEpoch <= !fEpoch;
    end
    else begin
      pc[1] <= ppc;
    end

    f2d.enq(Fetch2Decode{inst:inst, pc:pc[1], ppc:ppc, epoch:fEpoch});
  endrule

  rule doDecode(csrf.started);
    let inst = f2d.first.inst;
    let pc = f2d.first.pc;
    let ppc = f2d.first.ppc;
    let iEpoch = f2d.first.epoch;

    // Decode & Check stall
   	let dInst = decode(inst);
    $display(fshow(dInst));
    let stall = sb.search1(dInst.src1) || sb.search2(dInst.src2);

    if (!stall) begin 
      // reg read
      let rVal1 = isValid(dInst.src1) ? rf.rd1(validValue(dInst.src1)) : ?;
      let rVal2 = isValid(dInst.src2) ? rf.rd2(validValue(dInst.src2)) : ?;
      let csrVal = isValid(dInst.csr) ? csrf.rd(validValue(dInst.csr)) : ?;
      f2d.deq;
      if (iEpoch == fEpoch) begin // && !execRedirect.notEmpty 도 하면 cycle 개선이 되는데 why?
        d2e.enq(Decode2Execute{dInst:dInst, pc:pc, ppc:ppc, epoch:iEpoch, rVal1:rVal1, rVal2:rVal2, csrVal:csrVal});
        sb.insert(dInst.dst); // sb에 제대로 된 명령이면 dst를 추가 (mispredict 아닐 때)
      end
    end
    else begin
      if (execRedirect.notEmpty || iEpoch != fEpoch) f2d.deq; // stall 되어도 mispredict인 경우는 무시해야 함. 
    end

  endrule

  rule doExecute(csrf.started);
    let pcE = d2e.first.pc;
    let ppc = d2e.first.ppc;
    let iEpoch = d2e.first.epoch;
    let dInst = d2e.first.dInst;
    let rVal1 = d2e.first.rVal1;
    let rVal2 = d2e.first.rVal2;
    let csrVal = d2e.first.csrVal;
    d2e.deq;

    // epoch가 맞는 명령이면 실행함. 이때 확인하는 것은 제대로 predict 된 것인지.
    // 만약 mispredict이면 epoch를 바꾸고, execRedirect에 전달 -> 이후 들어오는 mispredict 명령들은 execRedirect fetch 전까지 무시됨
    let eInst = exec(dInst, rVal1, rVal2, pcE, ppc, csrVal);       
    $display(fshow(eInst));  

    if (iEpoch == eEpoch) begin 
      e2m.enq(Execute2Mem{eInst:eInst, flag:True});
      if (eInst.mispredict) begin
        eEpoch <= !eEpoch;
        pc[0] <= eInst.addr; // pc를 여기서 update (순서가 맞음 pc[0] 이니)
        execRedirect.enq(eInst.addr);
      end
    end
    else begin
      e2m.enq(Execute2Mem{eInst:eInst, flag:False});
    end
  endrule

  rule doMemory(csrf.started);
    let eInst = e2m.first.eInst;
    let flag = e2m.first.flag;
    e2m.deq;
    if (flag) begin
      case(eInst.iType)
        Ld :
        begin
          let d <- dMem.req(MemReq{op: Ld, addr:eInst.addr, data: ?});
          eInst.data = d;
        end
        St:
        begin
          let d <- dMem.req(MemReq{op: St, addr:eInst.addr, data:eInst.data});
        end
        Unsupported :
        begin
          $fwrite(stderr, "ERROR: Executing unsupported instruction\n");
          $finish;
        end
      endcase
    end
    m2w.enq(Mem2WriteBack{eInst:eInst, flag:flag});
  endrule

  rule doWriteback(csrf.started);
    let eInst = m2w.first.eInst;
    let flag = m2w.first.flag;
    m2w.deq;
    if (flag) begin
      if (isValid(eInst.dst)) begin
        rf.wr(fromMaybe(?, eInst.dst), eInst.data);
      end
      csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
    end
    sb.remove; 
  endrule

  method ActionValue#(CpuToHostData) cpuToHost;
    let retV <- csrf.cpuToHost;
    return retV;
  endmethod

  method Action hostToCpu(Bit#(32) startpc) if (!csrf.started);
    csrf.start(0);
    eEpoch <= False;
    fEpoch <= False;
    pc[0] <= startpc;
  endmethod

  interface iMemInit = iMem.init;
  interface dMemInit = dMem.init;

endmodule
