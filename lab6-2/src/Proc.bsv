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
  DecodedInst dInst;
  // Addr pc;
  // Addr ppc;
  // Bool epoch;
  // Data rVal1;
  // Data rVal2;
  // Data csrVal;
} Execute2Decode deriving(Bits, Eq);

typedef struct {
  ExecInst eInst;
  Bool flag;
} Execute2Mem deriving(Bits, Eq);

typedef struct {
  ExecInst eInst;
  Bool flag;
} Mem2WriteBack deriving(Bits, Eq);

typedef struct {
  ExecInst eInst;
  // Bool flag;
} Forward deriving(Bits, Eq);

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
  
  // PipelineFifo to construct 5-stage pipeline (deq < enq)
  Fifo#(1, Fetch2Decode) f2d <- mkPipelineFifo;
  Fifo#(1, Decode2Execute) d2e <- mkPipelineFifo;
  Fifo#(1, Execute2Mem) e2m <- mkPipelineFifo;
  Fifo#(1, Mem2WriteBack) m2w <- mkPipelineFifo;

  // Fifo for forwarding -> enq deq 순서가 역 방향이므로 BypassFIFO를 사용!. (enq < deq)
  Fifo#(1, Forward) m2e <- mkBypassFifo; // MEM 에서 m2e에 현재 명령 (e2m에 있는) 저장, 이후 EX 에서 m2e 보고 forwarding 판단
  Fifo#(1, Forward) w2e <- mkBypassFifo; // WB 에서 w2e에 현재 명령 (m2w에 있는) 저장, 이후 EX에서 w2e 보고 forwarding 판단 
  Fifo#(1, Execute2Decode) e2d <- mkBypassFifo;

 /* Lab 6-2: TODO) - Implement a 5-stage pipelined processor using a data forwarding (bypassing) logic. 
                   - To begin with, it is recommended that you reuse the code that you implemented in Lab 6-1.
                   - Define the correct bypassing units using BypassFiFo. */
  
  // Fetch
  rule doFetch(csrf.started);
    let inst = iMem.req(pc[1]); // pc[1]을 써서 바로 받아옴
    let ppc = pc[1] + 4;

    if (execRedirect.notEmpty) begin
      execRedirect.deq;
      pc[1] <= execRedirect.first;
      fEpoch <= !fEpoch;
    end
    else begin
      pc[1] <= ppc;
    end

    $display("Fetch from PC: %d", pc[1]);
    f2d.enq(Fetch2Decode{inst:inst, pc:pc[1], ppc:ppc, epoch:fEpoch});
  endrule

  // Decode
  rule doDecode(csrf.started);
    let inst = f2d.first.inst;
    let pc = f2d.first.pc;
    let ppc = f2d.first.ppc;
    let iEpoch = f2d.first.epoch;

    // Decode & Check stall
   	let dInst = decode(inst);

    // stall은 forwarding의 경우, load-use hazard 일 때만 진행되어야 함.
    // f2d에서 가져와서 decode한 inst (지금 실행하려는 inst) 랑 d2e에 있는 inst (이전 inst) 를 비교
    
    // 여기서 doDecode랑 doExecute가 잘 안되는 문제를 해결해야 함!
    // 

    Bool stall = False;
    if (e2d.notEmpty) begin
      let dInst_e2d = e2d.first.dInst;
      stall = (dInst_e2d.iType == Ld) && ((dInst_e2d.dst == dInst.src1) || (dInst_e2d.dst == dInst.src2));
      e2d.deq;
    end

    $display("stall: %d, Decoded inst:", stall);
    $display(fshow(dInst));

    if (!stall) begin 
      // reg read
      let rVal1 = isValid(dInst.src1) ? rf.rd1(validValue(dInst.src1)) : ?;
      let rVal2 = isValid(dInst.src2) ? rf.rd2(validValue(dInst.src2)) : ?;
      let csrVal = isValid(dInst.csr) ? csrf.rd(validValue(dInst.csr)) : ?;
      f2d.deq;
      if (iEpoch == fEpoch) begin // && !execRedirect.notEmpty 도 하면 cycle 개선이 되는데 why?
        d2e.enq(Decode2Execute{dInst:dInst, pc:pc, ppc:ppc, epoch:iEpoch, rVal1:rVal1, rVal2:rVal2, csrVal:csrVal});
      end
    end
    else begin
      if (execRedirect.notEmpty || iEpoch != fEpoch) f2d.deq; // stall 되어도 mispredict인 경우는 무시해야 함. 
    end
  endrule

  // Execute
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

    // forwarding 확인 후 각 경우 rVal을 update, 그 값을 exec에 반영 
    let fwdRVal1 = rVal1; 
    let fwdRVal2 = rVal2;
    Bool forwarded_src1_from_ex_mem = False;
    Bool forwarded_src2_from_ex_mem = False; // 각 val 2개에 대해 forwarding 따로 봐야 함!

    // 1. EX/MEM fowarding
    if (m2e.notEmpty) begin
      let eInst_m2e = m2e.first.eInst;
      m2e.deq(); 
      if (isValid(eInst_m2e.dst) && (validValue(eInst_m2e.dst) != 0)) begin
        if (eInst_m2e.dst == dInst.src1) begin
          fwdRVal1 = eInst_m2e.data;
          forwarded_src1_from_ex_mem = True;
          $display("Forwarding from EX/MEM to src1: reg %d, data %x", validValue(dInst.src1), eInst_m2e.data);
        end
        if (eInst_m2e.dst == dInst.src2) begin
          fwdRVal2 = eInst_m2e.data;
          forwarded_src2_from_ex_mem = True;
          $display("Forwarding from EX/MEM to src2: reg %d, data %x", validValue(dInst.src2), eInst_m2e.data);
        end
      end
    end

    // 2. MEM/WB forwarding (only when not EX/MEM forwarding)
    if (w2e.notEmpty) begin
      let eInst_w2e = w2e.first.eInst;
      w2e.deq(); 
      if (isValid(eInst_w2e.dst) && (validValue(eInst_w2e.dst) != 0)) begin
        if (!forwarded_src1_from_ex_mem && (eInst_w2e.dst == dInst.src1)) begin
          fwdRVal1 = eInst_w2e.data;
          $display("Forwarding from MEM/WB to src1: reg %d, data %x", validValue(dInst.src1), eInst_w2e.data);
        end
        if (!forwarded_src2_from_ex_mem && (eInst_w2e.dst == dInst.src2)) begin
          fwdRVal2 = eInst_w2e.data;
          $display("Forwarding from MEM/WB to src2: reg %d, data %x", validValue(dInst.src2), eInst_w2e.data);
        end
      end
    end

    // forwarding 이후 exec 실행
    let eInst = exec(dInst, fwdRVal1, fwdRVal2, pcE, ppc, csrVal);    
    if (iEpoch == eEpoch) begin 
      $display("Exec: iEpoch = %d eEpoch = %d", iEpoch, eEpoch);
      $display("With forwarding, executed inst:");
      $display(fshow(eInst));
      e2d.enq(Execute2Decode{dInst:dInst}); // for forwarding, 제대로 된 명령일 때만
      e2m.enq(Execute2Mem{eInst:eInst, flag:True});
      if (eInst.mispredict) begin
        eEpoch <= !eEpoch;
        pc[0] <= eInst.addr; // pc를 여기서 update (순서가 맞음 pc[0] 이니)
        execRedirect.enq(eInst.addr);
      end
    end
    else begin
      $display("Exec SKIP!!: iEpoch = %d eEpoch = %d");
      e2m.enq(Execute2Mem{eInst:eInst, flag:False});
    end
  endrule

  // Memory
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
      m2e.enq(Forward{eInst: eInst});
    end
    m2w.enq(Mem2WriteBack{eInst:eInst, flag:flag});
  endrule

  // WriteBack
  rule doWriteback(csrf.started);
    let eInst = m2w.first.eInst;
    let flag = m2w.first.flag;
    m2w.deq;
    if (flag) begin
      w2e.enq(Forward{eInst:eInst});
      if (isValid(eInst.dst)) begin
        rf.wr(fromMaybe(?, eInst.dst), eInst.data);
      end
      csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
    end
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
