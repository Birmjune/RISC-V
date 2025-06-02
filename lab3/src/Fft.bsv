import Vector::*;

import FftCommon::*;
import Fifo::*;

interface Fft; // FFT interface, enq and deq to FIFO
  method Action enq(Vector#(FftPoints, ComplexData) in);
  method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
endinterface

(* synthesize *)
module mkFftCombinational(Fft);
  Fifo#(2, Vector#(FftPoints, ComplexData)) inFifo <- mkCFFifo; // ComplexData with # of FftPoints, can store 2
  Fifo#(2, Vector#(FftPoints, ComplexData)) outFifo <- mkCFFifo;
  Vector#(NumStages, Vector#(BflysPerStage, Bfly4)) bfly <- replicateM(replicateM(mkBfly4)); // make all Bfly4 modules that we use 
  // bfly[stage][i] to access to each Bfly4 module; i'th Bfly4 module for each stage

  function Vector#(FftPoints, ComplexData) stage_f(StageIdx stage, Vector#(FftPoints, ComplexData) stage_in); // # of stage, stage input
    Vector#(FftPoints, ComplexData) stage_temp, stage_out;
    // combinational; use the for loop for # of Bfly stages
    for (FftIdx i = 0; i < fromInteger(valueOf(BflysPerStage)); i = i + 1)
    begin
      FftIdx idx = i * 4;
      Vector#(4, ComplexData) x;
      Vector#(4, ComplexData) twid;
      // Do the Bfly process
      for (FftIdx j = 0; j < 4; j = j + 1 )
      begin
        x[j] = stage_in[idx+j];
        twid[j] = getTwiddle(stage, idx+j);
      end
      let y = bfly[stage][i].bfly4(twid, x);

      // store the output in stage_temp
      for(FftIdx j = 0; j < 4; j = j + 1 )
        stage_temp[idx+j] = y[j];
    end
    // permute then return
    stage_out = permute(stage_temp);
    return stage_out;
  endfunction

  rule doFft; // rule for using the FFT function
    inFifo.deq;
    Vector#(4, Vector#(FftPoints, ComplexData)) stage_data; // stage_data[0] -> [1] -> [2] -> [3] (output)
    stage_data[0] = inFifo.first;

    for (StageIdx stage = 0; stage < 3; stage = stage + 1)
      stage_data[stage+1] = stage_f(stage, stage_data[stage]); // do stage_f for each step for next stagwe
    outFifo.enq(stage_data[3]);
  endrule

  method Action enq(Vector#(FftPoints, ComplexData) in);
    inFifo.enq(in);
  endmethod

  method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
    outFifo.deq;
    return outFifo.first;
  endmethod
endmodule

(* synthesize *)
module mkFftFolded(Fft);
  Fifo#(2, Vector#(FftPoints, ComplexData)) inFifo <- mkCFFifo;
  Fifo#(2, Vector#(FftPoints, ComplexData)) outFifo <- mkCFFifo;
  Vector#(BflysPerStage, Bfly4) bfly <- replicateM(mkBfly4); // less bfly4 modules

  Reg#(Vector#(FftPoints, ComplexData)) sReg <- mkRegU(); // for storing the FFT value data
  Reg#(StageIdx) stageCnt <- mkReg(0); // for storing stage count

  // You can copy & modify the stage_f function in the combinational implementation.
  function Vector#(FftPoints, ComplexData) stage_f(StageIdx stage, Vector#(FftPoints, ComplexData) stage_in); // # of stage, stage input
    Vector#(FftPoints, ComplexData) stage_temp, stage_out;
    // Folded, use the same Bfly4 modules for each stage
    for (FftIdx i = 0; i < fromInteger(valueOf(BflysPerStage)); i = i + 1)
    begin
      FftIdx idx = i * 4;
      Vector#(4, ComplexData) x; 
      Vector#(4, ComplexData) twid;
      // Do the Bfly process
      for (FftIdx j = 0; j < 4; j = j + 1 )
      begin
        x[j] = stage_in[idx+j];
        twid[j] = getTwiddle(stage, idx+j);
      end
      let y = bfly[i].bfly4(twid, x);

      // store the output in stage_temp
      for(FftIdx j = 0; j < 4; j = j + 1 )
        stage_temp[idx+j] = y[j];
    end
    // permute then return
    stage_out = permute(stage_temp);
    return stage_out;
  endfunction

  rule foldedFft;
    Vector#(FftPoints, ComplexData) sxIn;

    if (stageCnt == 0)
      begin sxIn = inFifo.first(); inFifo.deq; end
    else sxIn = sReg;

    let sxOut = stage_f(stageCnt, sxIn);
    if (stageCnt == 2) outFifo.enq(sxOut);
    else sReg <= sxOut;
    
    stageCnt <= (stageCnt == 2) ? 0 : stageCnt + 1;
  endrule

  method Action enq(Vector#(FftPoints, ComplexData) in);
    inFifo.enq(in);
  endmethod

  method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
    outFifo.deq;
    return outFifo.first;
  endmethod
endmodule

(* synthesize *)
module mkFftPipelined(Fft);
  Fifo#(2, Vector#(FftPoints, ComplexData)) inFifo <- mkCFFifo;
  Fifo#(2, Vector#(FftPoints, ComplexData)) outFifo <- mkCFFifo;
  Vector#(NumStages, Vector#(BflysPerStage, Bfly4)) bfly <- replicateM(replicateM(mkBfly4));

  Reg#(Maybe#(Vector#(FftPoints, ComplexData))) sReg1 <- mkReg(Invalid); // for storing the FFT value data
  Reg#(Maybe#(Vector#(FftPoints, ComplexData))) sReg2 <- mkReg(Invalid); // for storing the FFT value data

  // You can copy & modify the stage_f function in the combinational implementation.
  // There are no constrains on using rules as long as their functionality remains accurate.

  function Vector#(FftPoints, ComplexData) stage_f(StageIdx stage, Vector#(FftPoints, ComplexData) stage_in); // # of stage, stage input
    Vector#(FftPoints, ComplexData) stage_temp, stage_out;
    // combinational; use the for loop for # of Bfly stages
    for (FftIdx i = 0; i < fromInteger(valueOf(BflysPerStage)); i = i + 1)
    begin
      FftIdx idx = i * 4;
      Vector#(4, ComplexData) x;
      Vector#(4, ComplexData) twid;
      // Do the Bfly process
      for (FftIdx j = 0; j < 4; j = j + 1 )
      begin
        x[j] = stage_in[idx+j];
        twid[j] = getTwiddle(stage, idx+j);
      end
      let y = bfly[stage][i].bfly4(twid, x);

      // store the output in stage_temp
      for(FftIdx j = 0; j < 4; j = j + 1 )
        stage_temp[idx+j] = y[j];
    end
    // permute then return
    stage_out = permute(stage_temp);
    return stage_out;
  endfunction

  rule pipelinedFft(outFifo.notFull());
    StageIdx stage0 = 0;
    StageIdx stage1 = 1;
    StageIdx stage2 = 2;

    if (inFifo.notEmpty()) 
      begin sReg1 <= tagged Valid stage_f(stage0, inFifo.first()); inFifo.deq; end
      else sReg1 <= tagged Invalid; 

    case (sReg1) matches
      tagged Valid .sx1: sReg2 <= tagged Valid stage_f(stage1, sx1); 
      tagged Invalid: sReg2 <= tagged Invalid;
    endcase

    case (sReg2) matches
      tagged Valid .sx2: outFifo.enq(stage_f(stage2, sx2));
    endcase
  endrule

  method Action enq(Vector#(FftPoints, ComplexData) in);
    inFifo.enq(in);
  endmethod

  method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
    outFifo.deq;
    return outFifo.first;
  endmethod
endmodule
