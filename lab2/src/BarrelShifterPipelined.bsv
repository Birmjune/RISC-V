import Multiplexer::*;
import FIFO::*;
import FIFOF::*; // basically, 2 slots
import Vector::*;
import SpecialFIFOs::*;

/* Interface of the basic right shifter module */
interface BarrelShifterRightPipelined;
	method Action shift_request(Bit#(64) operand, Bit#(6) shamt, Bit#(1) val);
	method ActionValue#(Bit#(64)) shift_response();
endinterface

module mkBarrelShifterRightPipelined(BarrelShifterRightPipelined);
	/* use mkFIFOF for request-response interface.	*/

	// inelastic pipelining (using Reg)

	let inFifo <- mkFIFOF;
	let outFifo <- mkFIFOF;
	Reg#(Maybe#(Tuple3#(Bit#(64), Bit#(6), Bit#(1)))) sReg1 <- mkReg(Invalid);
	Reg#(Maybe#(Tuple3#(Bit#(64), Bit#(6), Bit#(1)))) sReg2 <- mkReg(Invalid);

	function Bit#(64) shift1(Bit#(64) oper, Bit#(2) shamt, Bit#(1) val);
		Bit#(64) shifted;
		for (Integer i = 0; i < 2; i = i + 1) begin
		   for (Integer j = 0; j < (64 - 2**i); j = j + 1) shifted[j] = oper[j + 2**i]; // 0 ~ 63-2**i
		   for (Integer j = 0; j < 2**i; j = j + 1) shifted[63 - j] = val; // 63 ~ 64-2**i
		   oper = multiplexer64(shamt[i], oper, shifted); // shift if 1 or not
		end
		return oper;
	endfunction

	function Bit#(64) shift2(Bit#(64) oper, Bit#(2) shamt, Bit#(1) val);
		Bit#(64) shifted;
		for (Integer i = 2; i < 4; i = i + 1) begin
		   for (Integer j = 0; j < (64 - 2**i); j = j + 1) shifted[j] = oper[j + 2**i]; // 0 ~ 63-2**i
		   for (Integer j = 0; j < 2**i; j = j + 1) shifted[63 - j] = val; // 63 ~ 64-2**i
		   oper = multiplexer64(shamt[i - 2], oper, shifted); // shift if 1 or not
		end
		return oper;
	endfunction

	function Bit#(64) shift3(Bit#(64) oper, Bit#(2) shamt, Bit#(1) val);
		Bit#(64) shifted;
		for (Integer i = 4; i < 6; i = i + 1) begin
		   for (Integer j = 0; j < (64 - 2**i); j = j + 1) shifted[j] = oper[j + 2**i]; // 0 ~ 63-2**i
		   for (Integer j = 0; j < 2**i; j = j + 1) shifted[63 - j] = val; // 63 ~ 64-2**i
		   oper = multiplexer64(shamt[i - 4], oper, shifted); // shift if 1 or not
		end
		return oper;
	endfunction

	rule shift_inelastic_pipelining (True);
		if (inFifo.notEmpty()) begin
			let operand = tpl_1(inFifo.first()); let shamt = tpl_2(inFifo.first()); let val = tpl_3(inFifo.first());
			sReg1 <= tagged Valid tuple3(shift1(operand, shamt[1:0], val), shamt, val); inFifo.deq();
		end
		else sReg1 <= tagged Invalid;

		case (sReg1) matches
			tagged Valid .sx1: sReg2 <= tagged Valid tuple3(shift2(tpl_1(sx1), tpl_2(sx1)[3:2], tpl_3(sx1)), tpl_2(sx1), tpl_3(sx1));
			tagged Invalid: sReg2 <= tagged Invalid;
		endcase

		case (sReg2) matches // if sReg2 is invalid, just ignore. don't send anything to outFifo
			tagged Valid .sx2: outFifo.enq(shift3(tpl_1(sx2), tpl_2(sx2)[5:4], tpl_3(sx2)));
		endcase		
	endrule

	method Action shift_request(Bit#(64) operand, Bit#(6) shamt, Bit#(1) val);
	// request shift (enq)
		inFifo.enq(tuple3(operand, shamt, val));
		// $display("%b >> %d", operand, shamt);
	endmethod

	method ActionValue#(Bit#(64)) shift_response();
	// get response (deq)
		let x = outFifo.first();
		// $display("%b", x);
		outFifo.deq();
		return x;
	endmethod
endmodule


/* Interface of the three shifter modules
 *
 * They have the same interface.
 * So, we just copy it using typedef declarations.
 */
interface BarrelShifterRightLogicalPipelined;
	method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
	method ActionValue#(Bit#(64)) shift_response();
endinterface

typedef BarrelShifterRightLogicalPipelined BarrelShifterRightArithmeticPipelined;
typedef BarrelShifterRightLogicalPipelined BarrelShifterLeftPipelined;

module mkBarrelShifterLeftPipelined(BarrelShifterLeftPipelined);
	/* TODO: Implement left shifter using the pipelined right shifter. */
	let bsrp <- mkBarrelShifterRightPipelined;

	method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
		let result = reverseBits(operand);
		bsrp.shift_request(result, shamt, 0);
	endmethod

	method ActionValue#(Bit#(64)) shift_response();
		let result <- bsrp.shift_response();
		return reverseBits(result);
	endmethod
endmodule

module mkBarrelShifterRightLogicalPipelined(BarrelShifterRightLogicalPipelined);
	/* TODO: Implement right logical shifter using the pipelined right shifter. */
	let bsrp <- mkBarrelShifterRightPipelined;

	method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
		bsrp.shift_request(operand, shamt, 0);
	endmethod

	method ActionValue#(Bit#(64)) shift_response();
		let result <- bsrp.shift_response();
		return result;
	endmethod
endmodule

module mkBarrelShifterRightArithmeticPipelined(BarrelShifterRightArithmeticPipelined);
	/* TODO: Implement right arithmetic shifter using the pipelined right shifter. */
	let bsrp <- mkBarrelShifterRightPipelined;

	method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
		bsrp.shift_request(operand, shamt, operand[63]);
	endmethod

	method ActionValue#(Bit#(64)) shift_response();
		let result <- bsrp.shift_response();
		return result;
	endmethod
endmodule

//========================================================================================

// Another pipelining implementation (inelastic, using FIFO and many rules)


// import Multiplexer::*;
// import FIFO::*;
// import FIFOF::*; // basically, 2 slots
// import Vector::*;
// import SpecialFIFOs::*;

// /* Interface of the basic right shifter module */
// interface BarrelShifterRightPipelined;
//    method Action shift_request(Bit#(64) operand, Bit#(6) shamt, Bit#(1) val);
//    method ActionValue#(Bit#(64)) shift_response();
// endinterface

// module mkBarrelShifterRightPipelined(BarrelShifterRightPipelined);
//    /* use mkFIFOF for request-response interface.   */

//    // elastic pipelining
   
//    /* inFifo → shift1Stage (1) → shift2Stage (2) → shift4Stage (3)
//       → shift8Stage (4) → shift16Stage (5) → shift32Stage (6) → outFifo */

//    let inFifo <- mkFIFOF;
//    let outFifo <- mkFIFOF;
//    let fifo1 <- mkFIFOF;
//    let fifo2 <- mkFIFOF;
//    let fifo3 <- mkFIFOF;
//    let fifo4 <- mkFIFOF;
//    let fifo5 <- mkFIFOF;

//    // elastic pipelining
//    rule stageshift1(inFifo.notEmpty() && fifo1.notFull());
//       Bit#(64) oper = tpl_1(inFifo.first());
//       Bit#(6) shiftAmt = tpl_2(inFifo.first());
//       Bit#(1) value = tpl_3(inFifo.first());

//       Bit#(64) shifted;
//       for (Integer j = 0; j < 63; j = j + 1) begin
//          shifted[j] = oper[j + 1]; // 0 ~ 63-2**i
//       end
//       for (Integer j = 0; j < 1; j = j + 1) begin
//          shifted[63 - j] = value; // 63 ~ 64-2**i
//       end
//       oper = multiplexer64(shiftAmt[0], oper, shifted); // shift if 1 or not
//       fifo1.enq(tuple3(oper, shiftAmt, value));
//       inFifo.deq();
//    endrule

//    rule stageshift2(fifo1.notEmpty() && fifo2.notFull());
//       Bit#(64) oper = tpl_1(fifo1.first());
//       Bit#(6) shiftAmt = tpl_2(fifo1.first());
//       Bit#(1) value = tpl_3(fifo1.first());

//       Bit#(64) shifted;
//       for (Integer j = 0; j < 62; j = j + 1) begin
//          shifted[j] = oper[j + 2]; // 0 ~ 63-2**i
//       end
//       for (Integer j = 0; j < 2; j = j + 1) begin
//          shifted[63 - j] = value; // 63 ~ 64-2**i
//       end
//       oper = multiplexer64(shiftAmt[1], oper, shifted); // shift if 1 or not
//       fifo2.enq(tuple3(oper, shiftAmt, value));
//       fifo1.deq();
//    endrule

//    rule stageshift4(fifo2.notEmpty() && fifo3.notFull());
//       Bit#(64) oper = tpl_1(fifo2.first());
//       Bit#(6) shiftAmt = tpl_2(fifo2.first());
//       Bit#(1) value = tpl_3(fifo2.first());

//       Bit#(64) shifted;
//       for (Integer j = 0; j < 60; j = j + 1) begin
//          shifted[j] = oper[j + 4]; // 0 ~ 63-2**i
//       end
//       for (Integer j = 0; j < 4; j = j + 1) begin
//          shifted[63 - j] = value; // 63 ~ 64-2**i
//       end
//       oper = multiplexer64(shiftAmt[2], oper, shifted); // shift if 1 or not
//       fifo3.enq(tuple3(oper, shiftAmt, value));
//       fifo2.deq();
//    endrule

//    rule stageshift8(fifo3.notEmpty() && fifo4.notFull());
//       Bit#(64) oper = tpl_1(fifo3.first());
//       Bit#(6) shiftAmt = tpl_2(fifo3.first());
//       Bit#(1) value = tpl_3(fifo3.first());

//       Bit#(64) shifted;
//       for (Integer j = 0; j < 56; j = j + 1) begin
//          shifted[j] = oper[j + 8]; // 0 ~ 63-2**i
//       end
//       for (Integer j = 0; j < 8; j = j + 1) begin
//          shifted[63 - j] = value; // 63 ~ 64-2**i
//       end
//       oper = multiplexer64(shiftAmt[3], oper, shifted); // shift if 1 or not
//       fifo4.enq(tuple3(oper, shiftAmt, value));
//       fifo3.deq();
//    endrule
   
//    rule stageshift16(fifo4.notEmpty() && fifo5.notFull());
//       Bit#(64) oper = tpl_1(fifo4.first());
//       Bit#(6) shiftAmt = tpl_2(fifo4.first());
//       Bit#(1) value = tpl_3(fifo4.first());

//       Bit#(64) shifted;
//       for (Integer j = 0; j < 48; j = j + 1) begin
//          shifted[j] = oper[j + 16]; // 0 ~ 63-2**i
//       end
//       for (Integer j = 0; j < 16; j = j + 1) begin
//          shifted[63 - j] = value; // 63 ~ 64-2**i
//       end
//       oper = multiplexer64(shiftAmt[4], oper, shifted); // shift if 1 or not
//       fifo5.enq(tuple3(oper, shiftAmt, value));
//       fifo4.deq();
//    endrule

//    rule stageshift32(fifo5.notEmpty() && outFifo.notFull());
//       Bit#(64) oper = tpl_1(fifo5.first());
//       Bit#(6) shiftAmt = tpl_2(fifo5.first());
//       Bit#(1) value = tpl_3(fifo5.first());

//       Bit#(64) shifted;
//       for (Integer j = 0; j < 32; j = j + 1) begin
//          shifted[j] = oper[j + 32]; // 0 ~ 63-2**i
//       end
//       for (Integer j = 0; j < 32; j = j + 1) begin
//          shifted[63 - j] = value; // 63 ~ 64-2**i
//       end
//       oper = multiplexer64(shiftAmt[5], oper, shifted); // shift if 1 or not
//       outFifo.enq(oper);
//       fifo5.deq();
//    endrule

//    method Action shift_request(Bit#(64) operand, Bit#(6) shamt, Bit#(1) val);
//    // request shift (enq)
//       inFifo.enq(tuple3(operand, shamt, val));
//    endmethod

//    method ActionValue#(Bit#(64)) shift_response();
//    // get response (deq)
//       outFifo.deq;
//       return outFifo.first();
//    endmethod
// endmodule


// /* Interface of the three shifter modules
//  *
//  * They have the same interface.
//  * So, we just copy it using typedef declarations.
//  */
// interface BarrelShifterRightLogicalPipelined;
//    method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
//    method ActionValue#(Bit#(64)) shift_response();
// endinterface

// typedef BarrelShifterRightLogicalPipelined BarrelShifterRightArithmeticPipelined;
// typedef BarrelShifterRightLogicalPipelined BarrelShifterLeftPipelined;

// module mkBarrelShifterLeftPipelined(BarrelShifterLeftPipelined);
//    /* TODO: Implement left shifter using the pipelined right shifter. */
//    let bsrp <- mkBarrelShifterRightPipelined;

//    method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
//       let result = reverseBits(operand);
//       bsrp.shift_request(result, shamt, 0);
//    endmethod

//    method ActionValue#(Bit#(64)) shift_response();
//       let result <- bsrp.shift_response();
//       return reverseBits(result);
//    endmethod
// endmodule

// module mkBarrelShifterRightLogicalPipelined(BarrelShifterRightLogicalPipelined);
//    /* TODO: Implement right logical shifter using the pipelined right shifter. */
//    let bsrp <- mkBarrelShifterRightPipelined;

//    method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
//       bsrp.shift_request(operand, shamt, 0);
//    endmethod

//    method ActionValue#(Bit#(64)) shift_response();
//       let result <- bsrp.shift_response();
//       return result;
//    endmethod
// endmodule

// module mkBarrelShifterRightArithmeticPipelined(BarrelShifterRightArithmeticPipelined);
//    /* TODO: Implement right arithmetic shifter using the pipelined right shifter. */
//    let bsrp <- mkBarrelShifterRightPipelined;

//    method Action shift_request(Bit#(64) operand, Bit#(6) shamt);
//       bsrp.shift_request(operand, shamt, operand[63]);
//    endmethod

//    method ActionValue#(Bit#(64)) shift_response();
//       let result <- bsrp.shift_response();
//       return result;
//    endmethod
// endmodule


