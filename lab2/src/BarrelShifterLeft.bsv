import BarrelShifterRight::*;

interface BarrelShifterLeft;
	method ActionValue#(Bit#(64)) leftShift(Bit#(64) val, Bit#(6) shiftAmt);
endinterface

module mkBarrelShifterLeft(BarrelShifterLeft);
	let bsr <- mkBarrelShifterRightLogical;
	method ActionValue#(Bit#(64)) leftShift(Bit#(64) val, Bit#(6) shiftAmt);
		/* TODO: Implement a left shifter using the given logical right shifter */
		// reverse, rightshift, and reverse again
		let result = reverseBits(val);
		result <- bsr.rightShift(result, shiftAmt);
		result = reverseBits(result);
		return result;
	endmethod
endmodule
