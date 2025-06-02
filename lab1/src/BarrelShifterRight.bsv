import Multiplexer::*;

interface BarrelShifterRight;
  method ActionValue#(Bit#(64)) rightShift(Bit#(64) val, Bit#(6) shiftAmt, Bit#(1) shiftValue);
endinterface

module mkBarrelShifterRight(BarrelShifterRight);
  method ActionValue#(Bit#(64)) rightShift(Bit#(64) val, Bit#(6) shiftAmt, Bit#(1) shiftValue);
    /* TODO: Implement right barrel shifter using six multiplexers. */
    Bit#(64) shifted;
    for (Integer i = 0; i < 6; i = i + 1) begin
      // make shifted
      for (Integer j = 0; j < (64 - 2**i); j = j + 1) begin
        shifted[j] = val[j + 2**i]; // 0 ~ 63-2**i
      end
      for (Integer j = 0; j < 2**i; j = j + 1) begin
        shifted[63 - j] = shiftValue; // 63 ~ 64-2**i
      end
      val = multiplexer64(shiftAmt[i], val, shifted); // shift if 1 or not
    end
    return val;
  endmethod
endmodule

interface BarrelShifterRightLogical;
  method ActionValue#(Bit#(64)) rightShift(Bit#(64) val, Bit#(6) shiftAmt);
endinterface

module mkBarrelShifterRightLogical(BarrelShifterRightLogical);
  let bsr <- mkBarrelShifterRight;
  method ActionValue#(Bit#(64)) rightShift(Bit#(64) val, Bit#(6) shiftAmt);
    /* TODO: Implement logical right shifter using the right shifter */
    Bit#(64) result <- bsr.rightShift(val, shiftAmt, 0);
    return result;
  endmethod
endmodule

typedef BarrelShifterRightLogical BarrelShifterRightArithmetic;

module mkBarrelShifterRightArithmetic(BarrelShifterRightArithmetic);
  let bsr <- mkBarrelShifterRight;
  method ActionValue#(Bit#(64)) rightShift(Bit#(64) val, Bit#(6) shiftAmt);
    /* TODO: Implement arithmetic right shifter using the right shifter */
    Bit#(64) result <- bsr.rightShift(val, shiftAmt, val[63]);
    return result;
  endmethod
endmodule
