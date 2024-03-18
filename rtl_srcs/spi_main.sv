`default_nettype none


//PL has 125 MHz clock
//ADC requires a 5 MHz (divide factor of 25) to operate at maximum frequency

//SPI interface is meant for the AD7920 IC, a 12-bit, 250 kSPS ADC
// TO-DO: Insert datasheet link here

//ADC has three connections (SCLK, SDATA, CS_L)

module spi_main #(parameter ADC_RESOLUTION = 12, CLK_DIVIDER = 25, QUIET_CYCLES = 8)
    (input logic fpga_clk, rst,

    input logic start_sampling,
    input logic miso, 

    output logic cs_L, sclk,
    output logic sampled_data_ready, 
    output logic [ADC_RESOLUTION-1:0] sampled_data
    );

    logic [4:0] clk_counter;
    logic [6:0] edge_counter;
    logic [2:0] quiet_counter;

    logic sclk_gen_active, rising_edge_transition;

    logic i_sclk, final_sclk;

    logic i_sampled_data_ready, final_sampled_data_ready;

    typedef enum {IDLE, SAMPLING, QUIET} state_t;

    state_t curr_state, next_state;

    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            final_sclk <= 1;
        end
        else begin
            final_sclk <= i_sclk;
        end
    end

    assign sclk = final_sclk;

    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            //clk counter is used to create the clk divider for SCLK
            clk_counter <= 0;
            //for each ADC reading, we need 32 edges total to get all the 12 bits of data
            edge_counter <= 0;

            rising_edge_transition <= 0;
            sclk_gen_active <= 0;

            //in the IDLE state, CLK is high
            i_sclk <= 1;

        end
        else begin
            rising_edge_transition <= 0;

            if (start_sampling && curr_state == IDLE) begin
                edge_counter <= 32;
                sclk_gen_active <= 1;
            end
            else if (edge_counter > 0) begin
                //the two conditionals below check for an edge transition
                if (clk_counter == CLK_DIVIDER-1) begin
                    edge_counter <= edge_counter -1;
                    clk_counter <= 0;

                    i_sclk <= ~i_sclk;

                    rising_edge_transition <= 1;
                end
                //this condition is reached first, since clk_counter is counting up
                else if (clk_counter == CLK_DIVIDER/2-1) begin
                    edge_counter <= edge_counter - 1;
                    clk_counter <= clk_counter + 1;

                    //from IDLE, CLK will go from 1 --> 0
                    i_sclk <= ~i_sclk;
                end
                else begin
                //gotta keep couting to make sure the SCLK is created correctly
                    clk_counter <= clk_counter + 1;
                end
            end

            else begin
                //here, it's inferred that clk_counter == 0, and edge_counter == 0
                sclk_gen_active <= 0;
            end

        end

    end


    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            i_sampled_data_ready <= 0;
            final_sampled_data_ready <= 0;
        end
        else if (edge_counter == 0 && sclk_gen_active) begin
            i_sampled_data_ready <= 1;
        end
        else if (sclk_gen_active) begin
            i_sampled_data_ready <= 0;
        end

        final_sampled_data_ready <= i_sampled_data_ready;

    end

    assign sampled_data_ready = final_sampled_data_ready;

    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            sampled_data <= 0;
        end
        //the very last edge transition will be from 0 to 1
        //at that point, all bits have been sampled and ADC is in three_state mode
        else if (rising_edge_transition && edge_counter > 1) begin
            //left-shift register
            sampled_data <= {sampled_data[10:0], miso};
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

    logic start_quiet_count;

    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            quiet_counter <= 0;
        end
        else begin
            if (start_quiet_count) begin
                quiet_counter <= quiet_counter + 1;
            end
        end
    end

    always_ff @(posedge fpga_clk) begin
        if (rst) begin
            cs_L <= 1;
        end
        else begin
            case (curr_state)
                IDLE: begin
                    if (start_sampling) begin
                        cs_L <= 0;
                    end
                    else begin
                        cs_L <= 1;
                    end
                end

                SAMPLING: begin
                    cs_L <= 0;
                end

                QUIET: begin
                    if (quiet_counter >= QUIET_CYCLES/2-1) begin
                        cs_L <= 1;
                    end
                    else begin
                        cs_L <= 0;
                    end
                end        

            endcase
        end
    end


    always_comb begin

        start_quiet_count = 0;

        case (curr_state) 
            IDLE: begin
                if (start_sampling) begin
                    next_state = SAMPLING;
                end 
                else begin
                    next_state = IDLE;
                end
            end

            SAMPLING: begin
                if (sclk_gen_active) begin
                    next_state = SAMPLING;
                end
                else begin
                    next_state = QUIET;
                end
            end

            //only stata where start_quiet_count is asserted
            QUIET: begin
                start_quiet_count = 1;

                if (quiet_counter == QUIET_CYCLES - 1) begin

                end
                else begin
                    next_state = QUIET;
                end

            end

            default: begin
                start_quiet_count = 0;
                next_state = IDLE;
            end


        endcase

    end
    
endmodule
