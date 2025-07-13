`timescale 1ns / 1ps

module i2c_master (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [6:0] addr,
    input wire [7:0] data,
    output wire scl,
    inout wire sda,
    output reg done,

    // Debug outputs for testbench visibility
    output reg [2:0] debug_state,
    output reg debug_sda_oe,
    output reg debug_sda_out
);

    // FSM states
    parameter IDLE = 3'd0, START = 3'd1, SEND_ADDR = 3'd2,
              ADDR_ACK = 3'd3, SEND_DATA = 3'd4,
              DATA_ACK = 3'd5, STOP = 3'd6;

    reg [2:0] state = IDLE;
    reg [3:0] bit_cnt = 0;
    reg [7:0] data_reg;
    reg [6:0] addr_reg;
    reg sda_out = 1;
    reg sda_oe = 1;
    reg [15:0] clk_div = 0;
    reg scl_int = 1;

    assign sda = sda_oe ? sda_out : 1'bz;
    assign scl = scl_int;

    // Clock divider to generate SCL (~100kHz from 50MHz)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 0;
            scl_int <= 1;
        end else begin
            if (clk_div == 250) begin
                scl_int <= ~scl_int;
                clk_div <= 0;
            end else begin
                clk_div <= clk_div + 1;
            end
        end
    end

    // Rising/falling edge detection for SCL
    reg scl_prev;
    always @(posedge clk) begin
        scl_prev <= scl_int;
    end
    wire scl_rising = (scl_int == 1) && (scl_prev == 0);
    wire scl_falling = (scl_int == 0) && (scl_prev == 1);

    // FSM triggered on SCL falling edge
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            sda_out <= 1;
            sda_oe <= 1;
            bit_cnt <= 0;

            // Init debug outputs
            debug_state <= IDLE;
            debug_sda_oe <= 1;
            debug_sda_out <= 1;
        end else if (scl_falling) begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        addr_reg <= addr;
                        data_reg <= data;
                        sda_out <= 1;
                        sda_oe <= 1;
                        state <= START;
                    end
                end

                START: begin
                    sda_out <= 0; // Start: SDA goes low while SCL high
                    bit_cnt <= 6;
                    state <= SEND_ADDR;
                end

                SEND_ADDR: begin
                    sda_out <= addr_reg[bit_cnt];
                    if (bit_cnt == 0)
                        state <= ADDR_ACK;
                    else
                        bit_cnt <= bit_cnt - 1;
                end

                ADDR_ACK: begin
                    sda_oe <= 0; // Release SDA for ACK
                    state <= SEND_DATA;
                    bit_cnt <= 7;
                end

                SEND_DATA: begin
                    sda_oe <= 1;
                    sda_out <= data_reg[bit_cnt];
                    if (bit_cnt == 0)
                        state <= DATA_ACK;
                    else
                        bit_cnt <= bit_cnt - 1;
                end

                DATA_ACK: begin
                    sda_oe <= 0; // Release SDA for ACK
                    state <= STOP;
                end

                STOP: begin
                    sda_oe <= 1;
                    sda_out <= 1; // SDA goes high while SCL is high
                    done <= 1;
                    state <= IDLE;
                end
            endcase

            // Update debug outputs
            debug_state <= state;
            debug_sda_oe <= sda_oe;
            debug_sda_out <= sda_out;
        end
    end
endmodule
