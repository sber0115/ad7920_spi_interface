

module spi_controller #(parameter ADC_RESOLUTION = 16, CS_TO_SCLK_CYCLES = 2,
                       CLK_DIVIDER = 25, QUIET_CYCLES = 4) 
    (
    input logic fpga_clk, rst,

    input logic start_sampling,

    input logic [ADC_RESOLUTION-1:0] i_tx_data,
    input logic i_tx_dv,
    output logic o_tx_ready,

    output logic o_rx_dv,
    output logic [ADC_RESOLUTION-1:0] o_rx_data,

    //SPI INTERFACE
    output logic o_spi_clk,
    input logic i_spi_miso,
    output logic o_spi_mosi,
    output logic o_spi_cs_L
    );

    logic r_is_busy;
    logic r_spi_clk;

    logic r_tx_ready;
    logic r_rx_dv;

    logic r_mosi;
    logic r_cs_L;

    logic [ADC_RESOLUTION-1:0] r_tx_data;
    logic [$clog2(ADC_RESOLUTION)-1:0] r_tx_index;
    
    logic [ADC_RESOLUTION-1:0] r_rx_data;
    logic [$clog2(ADC_RESOLUTION)-1:0] r_rx_index;

    assign o_spi_clk = r_spi_clk;
    assign o_spi_cs_L = r_cs_L;
    assign o_spi_mosi = r_mosi;

    assign o_tx_ready = r_tx_ready;
    
    assign o_rx_dv = r_rx_dv;
    assign o_rx_data = r_rx_data;

    typedef enum {IDLE, STARTUP, PROCESS, QUIET} state_t;

    state_t curr_state, next_state;

    logic [$clog2(CS_TO_SCLK_CYCLES)-1:0] cnt_cs_sclk;
    logic [$clog2(CLK_DIVIDER)-1:0] cnt_clk;
    logic [$clog2(2*ADC_RESOLUTION)-1:0] cnt_edge;
    logic [$clog2(QUIET_CYCLES)-1:0] cnt_quiet;

    //SCLK generation
    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            cnt_clk <= 0;
            cnt_edge <= 0;

            r_is_busy <= 0;
            r_spi_clk <= 1; //idle SPICLK = 1

            r_tx_ready <= 0;
            r_rx_dv <= 0;
        end 
        else begin

            r_rx_dv <= 0;

            if (~r_is_busy && (start_sampling || i_tx_dv)) begin
                cnt_edge <= (1 << ADC_RESOLUTION);

                r_is_busy <= 1;
                r_tx_ready <= 0;
            end
            else if (cnt_edge > 0) begin
                if (cnt_clk == CLK_DIVIDER/2-1) begin
                    cnt_edge <= cnt_edge - 1;

                    r_spi_clk <= ~r_spi_clk;
                end
                else if (cnt_clk == CLK_DIVIDER-1) begin
                    cnt_edge <= cnt_edge - 1;

                    r_spi_clk <= ~r_spi_clk;
                end

                cnt_clk <= cnt_clk + 1;
            end
            else begin
                //when this case is reach, it's assumed cnt_edge == 0, and cnt_clk == 0
                r_tx_ready <= 1;

                //this r_is_busy check makes sure we don't assert rx_dv when
                //the controller has been sitting idle (no transaction had initiated)
                if (r_is_busy) begin
                    r_rx_dv <= 1;
                    r_is_busy <= 0;
                end 

            end
        end
    end


    //note, the tx_data must be clocked in on the fpga_clk domain
    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            r_tx_data <= 0;
        end
        else begin
            if (i_tx_dv) begin
                r_tx_data <= i_tx_data;
            end
        end
    end

    //here, we are referencing data from a different clock domain (r_tx_data)
    //"crossing clock domains, from fpga_clk to negedge r_spi_clk"
    //negedge r_spi_clk domain

    //shifting data out on the negative SCLK
    always_ff @(negedge r_spi_clk) begin
        if (rst) begin
            r_mosi <= 0;
            r_tx_index <= (1 << $clog2(ADC_RESOLUTION));
        end 
        else begin
            //TX data is sent MSB first
            r_tx_index <= r_tx_index - 1;
            r_mosi <= r_tx_data[r_tx_index];
        end
    end
    

    //sampling data on the positive SCLK
    always_ff @(posedge r_spi_clk) begin
        if (rst) begin
            r_rx_data <= 0;
            r_rx_index <= (1 << $clog2(ADC_RESOLUTION));
        end
        else begin
            //RX data is read in, MSB first
            //left-shifting the bit in, so first bit will end up as MSB

            //r_rx_index <= r_rx_index - 1;
            //r_rx_data[r_rx_index] <= i_spi_miso;
            r_rx_data <= {r_rx_data[ADC_RESOLUTION-2:0], i_spi_miso};
        end
    end


    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            curr_state <= IDLE;
        end
        else begin
            curr_state <= next_state;
        end
    end


    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            cnt_cs_sclk <= 0;
            cnt_quiet <= 0;

            r_cs_L <= 1;
        end 
        else begin
            r_cs_L <= 1;

            case (curr_state)

                IDLE: begin
                    if (~r_is_busy && (start_sampling || i_tx_dv)) begin
                        next_state <= STARTUP;
                        cnt_cs_sclk <= (1 << $clog2(CS_TO_SCLK_CYCLES));
                        cnt_quiet <= (1 << $clog2(QUIET_CYCLES));
                    end
                    else begin
                        next_state <= IDLE;
                    end
                end

                STARTUP: begin
                    if (cnt_cs_sclk == 0) begin
                        next_state <= PROCESS;
                    end
                    else begin
                        next_state <= STARTUP;
                        cnt_cs_sclk <= cnt_cs_sclk - 1;
                    end
                end

                PROCESS: begin
                    if (~r_is_busy) begin
                        next_state <= QUIET;
                    end
                    else begin
                        next_state <= PROCESS;
                        r_cs_L <= 0;
                    end
                end

                QUIET: begin
                    if (cnt_quiet == 0) begin
                        next_state <= IDLE;
                    end
                    else begin
                        next_state <= QUIET;
                        cnt_quiet <= cnt_quiet - 1;
                        r_cs_L <= 0;
                    end
                end

            endcase
        end

    end


endmodule