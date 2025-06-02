package HelloWorld;
	String hello = "HelloWorld";
	String bye = "Bye!";

	(* synthesize *)
	module mkHelloWorld(Empty);
		/* TODO: Implement HelloWorld module */
		
		Reg#(Bit#(3)) counter <- mkReg(0);

		rule say_hello(counter < 5);
			$display(hello);
			counter <= counter + 1;
		endrule
		
		rule say_bye(counter == 5);
			$display(bye);
			$finish;
		endrule

	endmodule
endpackage
// package HelloWorld;
// (* synthesize *)
// 	module mkProb2(Empty);
// 		Reg#(Bit#(6)) k <- mkReg(0);

// 		rule multistep (k < 32);
// 			k <= k + 1;
// 		endrule
// 	endmodule
// endpackage
