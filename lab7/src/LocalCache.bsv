import Types::*;
import CMemTypes::*;
import CacheTypes::*;
import Fifo::*;
import RegFile::*;
import Vector::*;
import MemInit::*; 

interface Cache;
	method Action req(MemReq r);
	method ActionValue#(Data) resp;

 	method ActionValue#(CacheMemReq) memReq;
 	method Action memResp(Line r);

	method Data getMissCnt;
	method Data getTotalReq;
endinterface

typedef enum {Ready, StartMiss, SendFillReq, WaitFillResp} CacheStatus deriving (Bits, Eq);


(*synthesize*)
module mkCacheSetAssociative (Cache);
	Vector#(LinesPerSet, RegFile#(CacheIndex, Line))				  dataArray <- replicateM(mkRegFileFull);
	Vector#(LinesPerSet, RegFile#(CacheIndex, Maybe#(CacheTag)))       tagArray <- replicateM(mkRegFileFull);
	Vector#(LinesPerSet, RegFile#(CacheIndex, Bool))				 dirtyArray <- replicateM(mkRegFileFull);
	Vector#(LinesPerSet, RegFile#(CacheIndex, SetOffset)) lruArray <- replicateM(mkRegFileFull);

	Reg#(Bit#(TAdd#(SizeOf#(CacheIndex), 1))) init <- mkReg(0);
	Reg#(CacheStatus)					    status <- mkReg(Ready);
	Reg#(CacheStatus)					    testflag <- mkReg(Ready);
	Reg#(Maybe#(SetOffset)) 		targetLine <- mkReg(Invalid);

	Fifo#(1, Data)  hitQ <- mkBypassFifo;
	Reg#(MemReq) missReq <- mkRegU;

	Fifo#(2, CacheMemReq) memReqQ <- mkCFFifo;
	Fifo#(2, Line) 		 memRespQ <- mkCFFifo;

	Reg#(Data) missCnt <- mkReg(0);
	Reg#(Data)  reqCnt <- mkReg(0);

	function CacheIndex getIdx(Addr addr) = truncate(addr >> (2 + fromInteger(valueOf(SizeOf#(BlockOffset))))); 
	function CacheTag getTag(Addr addr) = truncateLSB(addr);
	function BlockOffset getOffset(Addr addr) = truncate(addr >> 2); 

	function Addr getBlockAddr(CacheTag tag, CacheIndex idx);
		BlockOffset def_offset = 0;
		Addr addr = {tag, idx, def_offset, 2'b0}; 
		return addr;
	endfunction

	function Maybe#(SetOffset) checkHit(CacheTag tag, CacheIndex idx);
		// Returns the SetOffset when cache hit occurs at given idx with the given tag.
		// It happens by checking the validity and tag value.
		Maybe#(SetOffset) ret = Invalid;

		for(Integer i = 0; i < valueOf(LinesPerSet); i = i + 1)
		begin
			let tagArrayVal = tagArray[i].sub(idx);

			if(isValid(tagArrayVal) && (fromMaybe(?, tagArrayVal) == tag) )
			begin
				ret = tagged Valid fromInteger(i);
			end
		end
		return ret;
	endfunction

	function Maybe#(SetOffset) findInvalid(CacheIndex idx);
		// Returns the SetOffset of a invalid cache slot at given idx.
		// If no one exists, returns Invalid.
		Maybe#(SetOffset) ret = Invalid;

		for(Integer i = 0; i < valueOf(LinesPerSet); i = i+1)
		begin
			if(!isValid(tagArray[i].sub(idx)))
			begin
				ret = tagged Valid fromInteger(i);
			end
		end
		return ret;
	endfunction

    function SetOffset findLRU(CacheIndex idx);
		// Returns the exact LRU.
		return lruArray[valueOf(LinesPerSet) - 1].sub(idx);
	endfunction

	function Action updateLRUArray(CacheIndex idx, SetOffset lineNum);
		// update lruArray to help finding LRU.
	    return action
			// find the index of lineNum element in the LRUArray.
	       	Integer idxInLRUArray = 0;
        	for (Integer i = 1; i < valueOf(LinesPerSet); i = i+1)
        	begin
            	if (lineNum == lruArray[i].sub(idx)) begin
            		idxInLRUArray = i;
          		end
			end

			// right shift elements before lineNum.
          	for (Integer i = 1;  i<= idxInLRUArray; i = i+1)
          	begin
            	lruArray[i].upd(idx, lruArray[i-1].sub(idx));
          	end

          	// put lineNum at the front.
          	lruArray[0].upd(idx, lineNum);
	    endaction;
    endfunction

	/* You can use this function in rules(startMiss,waitFillResp) when implement set associative cache */
	function SetOffset findLineToUse(CacheIndex idx);
		// if empty line exists, use that line.
		// if empty line doesn't exist, use LRU.
		let emptyLine = findInvalid(idx);
		if (isValid(emptyLine)) begin
			return fromMaybe(?, emptyLine);
		end else begin
			return findLRU(idx);
		end
	endfunction

 	let inited = truncateLSB(init) == 1'b1;

	rule initialize(!inited);
		init <= init + 1;
		for(Integer i = 0; i< valueOf(LinesPerSet);i = i+1)
		begin
			tagArray[i].upd(truncate(init), Invalid);
			dirtyArray[i].upd(truncate(init), False);
			lruArray[i].upd(truncate(init), fromInteger(i));
		end
	endrule

	// When cache miss: proc -> cache -> mem -> cache -> proc
	// -> 1: check if miss
	// -> 2: check dirty array & send wb req to update mem (if needed) + send read req to mem 
	// -> 3: send data
	// -> 4: see missreq, and send data to CPU (act like data is in cache)

	rule startMiss(status == StartMiss);
		/* TODO: Implement here */
		let r = missReq;
		let cI = getIdx(r.addr);
    	let cT = getTag(r.addr);

		let lineToUse = findLineToUse(cI);

		Bool isDirty = dirtyArray[lineToUse].sub(cI);
		Maybe#(CacheTag) oldTag = tagArray[lineToUse].sub(cI);
		let burstLen = fromInteger(valueOf(WordsPerBlock)); // Bit# type으로 change

		if (isDirty && isValid(oldTag)) begin 
			// dirty인 경우 먼저 그 부분에 쓰인 값을 mem에 update
			let oldTagVal = validValue(oldTag);
			let oldAddr = getBlockAddr(oldTagVal, cI);
			let updateData = dataArray[lineToUse].sub(cI);
			memReqQ.enq(CacheMemReq{op:St, addr:oldAddr, data:updateData, burstLength:burstLen});
		end
		status <= SendFillReq;
	endrule

	rule sendFillReq(status == SendFillReq);
		/* TODO: Implement here */
		// get data from mem
		let r = missReq;
		let cI = getIdx(r.addr);
    	let cT = getTag(r.addr);
		let newAddr = getBlockAddr(cT, cI);
		let burstLen = fromInteger(valueOf(WordsPerBlock));

		memReqQ.enq(CacheMemReq{op:Ld, addr: newAddr, data:?, burstLength:burstLen});
		status <= WaitFillResp;
	endrule

	rule waitFillResp(status == WaitFillResp);
		/* TODO: Implement here */
		let respData = memRespQ.first;
		memRespQ.deq;

		let r = missReq;
		let cI = getIdx(r.addr);
		let cT = getTag(r.addr);
    	let bO = getOffset(r.addr);
		let lineToUpdate = findLineToUse(cI);

		tagArray[lineToUpdate].upd(cI, tagged Valid cT);
		dataArray[lineToUpdate].upd(cI, respData);
		dirtyArray[lineToUpdate].upd(cI, False);
		hitQ.enq(respData[bO]);

		updateLRUArray(cI, lineToUpdate);
		status <= Ready;
	endrule

	method Action req(MemReq r) if (status == Ready && inited);
		// If hit, then
		//     - If r.op == Ld, return the cache value
		//     - If r.op == St, change the cache value and set as dirty
		// If not-hit, then
		//     - If r.op == Ld, send memory load request and wait.
		//     - If r.op == St, send store request.

		/* TODO: Implement here */
		CacheIndex cI = getIdx(r.addr);
		CacheTag cT = getTag(r.addr);
		BlockOffset bO = getOffset(r.addr);

		let hit = checkHit(cT, cI);

		if (isValid(hit)) begin
			let way = validValue(hit);
			updateLRUArray(cI, way);
			case(r.op)
				Ld: begin
					let wordData = dataArray[way].sub(cI);
					hitQ.enq(wordData[bO]);
				end
				St: begin
					let newLine = dataArray[way].sub(cI);
					newLine[bO] = r.data;
					dirtyArray[way].upd(cI, True);
					dataArray[way].upd(cI, newLine);
				end
			endcase
		end 
		else begin
			case (r.op)
				Ld: begin 
					missReq <= r;
					status <= StartMiss;
				end
				St: begin // Load인 경우만 cache에 값 반환! (그 word 하나만)
					Line writeData = replicate(?); 
					writeData[0] = r.data; 
					memReqQ.enq(CacheMemReq{op:St, addr: r.addr, data: writeData, burstLength: 1});
				end
			endcase
		end

		/* DO NOT MODIFY BELOW HERE! */
		if(!isValid(hit))
		begin
			missCnt <= missCnt + 1;
		end
		reqCnt <= reqCnt + 1;  
	endmethod

	method ActionValue#(Data) resp;
		hitQ.deq;
		return hitQ.first;
	endmethod

	method ActionValue#(CacheMemReq) memReq;
		memReqQ.deq;
		return memReqQ.first;
	endmethod

	method Action memResp(Line r);
		memRespQ.enq(r);
	endmethod

	method Data getMissCnt;
		return missCnt;
	endmethod

	method Data getTotalReq;
		return reqCnt;
	endmethod
endmodule

(*synthesize*)
module mkCache (Cache);
	Cache cacheSetAssociative <- mkCacheSetAssociative;
	return cacheSetAssociative;
endmodule
