`timescale 1ns/1ns

//SPI_CLK --> 5 MHz, 200ns
//FGPA_CLK --> 125 MHz, 8ns

module testbench();

    //inputs
    logic fpga_clk, rst_btn;

    logic start_sampling_btn;
    logic adc_sdata;

    //outputs
    logic adc_sclk, adc_cs_L;
    logic [3:0] LED;

    top dut (.*);

    initial begin
        fpga_clk = 1'b0;
        rst = 1'b1;

        repeat (20) #4 fpga_clk = ~clk;

        $finish();
    end

    initial begin
        repeat (2) @(posedge fpga_clk);
        rst = 0;
    end 


endmodule
