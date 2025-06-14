/*

Copyright (C) 2012

Arvind <arvind@csail.mit.edu>
Derek Chiou <derek@ece.utexas.edu>
Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


import Types::*;
import ProcTypes::*;
import Vector::*;

(* noinline *)
function DecodedInst decode(Instruction inst);
	DecodedInst dInst = ?;

	// opcode and imm for the instructions 
	Opcode opcode = inst[  6 :  0 ];
	let rd        =        inst[ 11 :  7 ];
	let funct3    =        inst[ 14 : 12 ];
	let rs1       =        inst[ 19 : 15 ];
	let rs2       =        inst[ 24 : 20 ];
//	let funct7    =        inst[ 31 : 25 ];
	let aluSel    =        inst[30]; // select between Add/Sub, Srl/Sra

	// the type is decided by the "Immediate Values"
	Data immI   = signExtend(inst[31:20]);
	Data immS   = signExtend({ inst[31:25], inst[11:7] });
	Data immB   = signExtend({ inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
	Data immU   = signExtend({ inst[31:12], 12'b0 });
	Data immJ   = signExtend({ inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});

	case (opcode)

	/* TODO: Finish implementing decode.bsv */

		opOp: begin
			dInst.iType = Alu;
			dInst.aluFunc = case (funct3)
				fnADD: aluSel == 0 ? Add : Sub;
				fnSLL: Sll;
				fnSLT: Slt;
				fnSLTU: Sltu;
				fnXOR: Xor;
				fnSR: aluSel == 0 ? Srl : Sra;
				fnOR: Or;
				fnAND: And;
			endcase;
			dInst.brFunc = NT;
			dInst.dst  = tagged Valid rd;
			dInst.src1 = tagged Valid rs1;
			dInst.src2 = tagged Valid rs2;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Invalid;
		end

		opOpImm: begin
			dInst.iType = Alu;
			dInst.aluFunc = case (funct3)
				fnADD: Add;
				fnSLL: Sll;
				fnSLT: Slt;
				fnSLTU: Sltu;
				fnXOR: Xor;
				fnSR: aluSel == 0 ? Srl : Sra;
				fnOR: Or;
				fnAND: And;
			endcase;
			dInst.brFunc = NT;
			dInst.dst  = tagged Valid rd;
			dInst.src1 = tagged Valid rs1;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immI;
		end

		opJal: begin
			dInst.iType = J;
			dInst.aluFunc = ?;
			dInst.brFunc = AT;
			dInst.dst = tagged Valid rd;
			dInst.src1 = tagged Invalid;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immJ;
		end

		opJalr: begin
			dInst.iType = Jr;
			dInst.aluFunc = ?;
			dInst.brFunc = AT;
			dInst.dst = tagged Valid rd;
			dInst.src1 = tagged Valid rs1;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immI;
		end
		
		opBranch: begin
			Maybe#(BrFunc) brF =
			  case(funct3)
				fnBEQ: tagged Valid Eq;
				fnBNE: tagged Valid Neq;
				fnBLT: tagged Valid Lt;
				fnBGE: tagged Valid Ge;
				fnBLTU: tagged Valid Ltu;
				fnBGEU: tagged Valid Geu;
				default: Invalid;
			  endcase;
			
			dInst.iType  = isValid(brF) ? Br : Unsupported; // check if brF is a valid branch compare
			dInst.aluFunc = ?;
			dInst.brFunc  = fromMaybe(?, brF); // if valid get brf
			dInst.dst     = Invalid;
			dInst.src1    = tagged Valid rs1;
			dInst.src2    = tagged Valid rs2;
			dInst.csr = tagged Invalid;
			dInst.imm     = tagged Valid immB; // offset added to PC
		end

		opLoad: begin // only support lw (32 bit architecture)
			dInst.iType = ((funct3 == fnLW) ? Ld : Unsupported);
			dInst.aluFunc = Add;
			dInst.brFunc = NT;
			dInst.dst = tagged Valid rd;
			dInst.src1 = tagged Valid rs1;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immI;
		end

		opStore: begin // only support sw (32 bit architecture)
			dInst.iType = ((funct3 == fnSW) ? St : Unsupported);
			dInst.aluFunc = Add;
			dInst.brFunc = NT;
			dInst.dst = tagged Invalid;
			dInst.src1 = tagged Valid rs1;
			dInst.src2 = tagged Valid rs2;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immS;
		end

		/* DO NOT MODIFY BELOW HERE! */
		opLui: begin // rd = immU + r0
			dInst.iType = Alu;
			dInst.aluFunc = Add;
			dInst.brFunc = NT;
			dInst.dst = tagged Valid rd;
			dInst.src1 = tagged Valid 0;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immU;
		end

		opAuipc: begin
			dInst.iType = Auipc;
			dInst.aluFunc = ?;
			dInst.brFunc = NT;
			dInst.dst = tagged Valid rd;
			dInst.src1 = tagged Invalid;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Valid immU;
		end

		opSystem: begin
			// CSRRC(I) CSRRWI CSRRSI SCALL not implemented
			case (funct3)
				fnCSRRW: begin
					// only support rd = 0 (no read of csr)
					dInst.iType = rd == 0 ? Csrw : Unsupported;
				end
				fnCSRRS: begin
					// only support rs1 = 0 (no write to csr)
					dInst.iType = rs1 == 0 ? Csrr : Unsupported;
				end
				default: dInst.iType =  Unsupported;
			endcase
			dInst.aluFunc = ?;
			dInst.brFunc = NT;
			dInst.dst = tagged Valid rd;
			dInst.src1 = tagged Valid rs1;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Valid truncate(immI);
			dInst.imm  = tagged Invalid;
		end

		default: begin
			dInst.iType = Unsupported;
			dInst.aluFunc = ?;
			dInst.brFunc = NT;
			dInst.dst = tagged Invalid;
			dInst.src1 = tagged Invalid;
			dInst.src2 = tagged Invalid;
			dInst.csr = tagged Invalid;
			dInst.imm = tagged Invalid;
		end
	endcase

	// no write to x0
	if(dInst.dst matches tagged Valid .dst &&& dst == 0) begin
		dInst.dst = tagged Invalid;
	end

	return dInst;
endfunction

