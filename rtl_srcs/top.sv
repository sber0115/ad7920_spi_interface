`default_nettype none

//Pins 1-4, 7-10 on P-Mod are usable

// FPGA Pin Definitions:
// adc_sdata --> V12
// adc_sclk -->  W16
// adc_cs_L -->  J15

module top (
    input logic fpga_clk, rst_btn,

    input logic start_sampling_btn,
    input logic adc_sdata,

    output logic adc_sclk, adc_cs_L,
    output logic [3:0] LED,
    output logic LED_5
);

    logic [11:0] sampled_data_sig;
    logic sampling_done;

    assign LED = {sampled_data_sig[11:10], sampled_data_sig[1:0]};

    assign LED_5 = sampling_done;


    spi_main spi_main_inst (.fpga_clk(fpga_clk), .rst(rst_btn),
                   .start_sampling(start_sampling_btn), .miso(adc_sdata),

                   .sclk(adc_sclk), .cs_L(adc_cs_L), 
                   .sampled_data_ready(sampling_done), .sampled_data(sampled_data_sig));
    
endmodule


