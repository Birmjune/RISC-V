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
//import Cop::*;


typedef enum {Fetch, Execute, Memory, WriteBack} Stage deriving(Bits, Eq);



(*synthesize*)
module mkProc(Proc);
  Reg#(Addr) pc  <- mkRegU;
  RFile rf  <- mkRFile;
  IMemory iMem  <- mkIMemory; // instruction memory
  DMemory dMem  <- mkDMemory; // data memory
  CsrFile csrf <- mkCsrFile;

  Reg#(ProcStatus) stat	<- mkRegU;
  Reg#(Stage) stage	<- mkRegU; // stage register

  Fifo#(1,ProcStatus) statRedirect <- mkBypassFifo;

  Reg#(Instruction)	f2e <- mkRegU; // store Instruction (32 bit binary)
  Reg#(ExecInst) f2ex <- mkRegU; // store executed instruction

  Bool memReady = iMem.init.done() && dMem.init.done();
  rule test (!memReady);
    let e = tagged InitDone;
    iMem.init.request.put(e);
    dMem.init.request.put(e);
  endrule

  // the five steps
  // IF -> ID -> EX -> MEM -> WB

  rule doFetch(csrf.started && stat == AOK && stage == Fetch); // IF
    let inst = iMem.req(pc);
    $display("Fetch : from Pc %d , expanded inst : %x, \n", pc, inst, showInst(inst));
    stage <= Execute;
    f2e <= inst;  
  endrule

  rule doExecute(csrf.started && stat == AOK && stage == Execute); // ID + EX
    let inst = f2e; // get instruction

	  // Decode
    DecodedInst dInst = decode(inst);
    $display(fshow(dInst));

    // read general purpose register values 
    let rVal1 = isValid(dInst.src1) ? rf.rd1(validValue(dInst.src1)) : ?;
    let rVal2 = isValid(dInst.src2) ? rf.rd2(validValue(dInst.src2)) : ?;
    let csrVal = isValid(dInst.csr) ? csrf.rd(validValue(dInst.csr)) : ?;
  
    // Execute
    ExecInst eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal); 
    stage <= ((eInst.iType == Ld || eInst.iType == St) ? Memory : WriteBack); // next stage will be MEM or WB
    f2ex <= eInst;
  endrule

  rule doMemory(csrf.started && stat == AOK && stage == Memory); // MEM
    let eInst = f2ex; // get executed instruction
    let iType = eInst.iType;
    case(iType)
      Ld: begin
        eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        f2ex <= eInst; // update data (to the value that we read from memory)
	    end
		  St: begin
        let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
		  end
    endcase
    stage <= WriteBack;
  endrule
  
  rule doWriteBack(csrf.started && stat == AOK && stage == WriteBack); // WB
    let eInst = f2ex;
    if (isValid(eInst.dst)) begin
		  rf.wr(fromMaybe(?, eInst.dst), eInst.data);
    end

    pc <= eInst.brTaken ? eInst.addr : pc + 4;

    csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
    stage <= Fetch;
  endrule

  method ActionValue#(CpuToHostData) cpuToHost;
    let retV <- csrf.cpuToHost;
    return retV;
  endmethod

  method Action hostToCpu(Bit#(32) startpc) if (!csrf.started);
    csrf.start(0);
    stage <= Fetch;
    pc <= startpc;
    stat <= AOK;
  endmethod

  interface iMemInit = iMem.init;
  interface dMemInit = dMem.init;

endmodule

  // rule doRest(csrf.started && stat == AOK && stage == Execute);
  //   /* TODO: Divide the doExecute rule into doExecute, doMemory and doWriteBack rules */
  //   /* The doMemory rule should be skipped whenever it is not required. */
  //   // doExecute: ID, EX
  //   // doMemory: MEM
  //   // doWriteBack: WB

  //   let inst = f2e;

	//   /* Decode */
  //   DecodedInst dInst = decode(inst);
  //   $display(fshow(dInst));

  //   // read general purpose register values 
  //   let rVal1 = isValid(dInst.src1) ? rf.rd1(validValue(dInst.src1)) : ?;
  //   let rVal2 = isValid(dInst.src2) ? rf.rd2(validValue(dInst.src2)) : ?;
  //   let csrVal = isValid(dInst.csr) ? csrf.rd(validValue(dInst.csr)) : ?;

  //   /* Execute */
  //   ExecInst eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);  

  //   /* Memory */
  //   let iType = eInst.iType;
  //   case(iType)
  //     Ld: begin
  //       eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
	//     end
	// 	  St: begin
  //       let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
	// 	  end
  //   endcase


	//   /* WriteBack */
  //   if(isValid(eInst.dst)) begin
	// 	  rf.wr(fromMaybe(?, eInst.dst), eInst.data);
  //   end

  //   pc <= eInst.brTaken ? eInst.addr : pc + 4;

  //   csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
  //   stage <= Fetch;
  // endrule
  