
/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena,
    input  wire clk,
    input  wire rst_n
);

    wire hsync;
    wire vsync;

    wire [1:0] R;
    wire [1:0] G;
    wire [1:0] B;

    wire video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

    assign uio_out = 0;
    assign uio_oe = 0;

    wire _unused_ok = &{ena, ui_in, uio_in};

    reg [9:0] counter;

    hvsync_generator hvsync_gen(
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );


  wire flag = (pix_x >= 20 && pix_x < 620 && pix_y >= 60 && pix_y < 420);

  wire black = flag && (pix_y >= 60 && pix_y < 180); //black
  wire red = flag && (pix_y >= 180 && pix_y < 300); //red
  wire gold = flag && (pix_y >= 300 && pix_y < 420); //gold

  wire border = (pix_x >= 18 && pix_x < 622 && pix_y >= 58 && pix_y < 422) && !flag;

  assign R = (video_active && (red || gold || border)) ? 2'b11 : 2'b00;
  assign G = (video_active && (gold || border)) ? (gold ? 2'b10 : 2'b11) : 2'b00;
  assign B = (video_active && border) ? 2'b11 : 2'b00;


    always @(posedge vsync or negedge rst_n) begin
        if (~rst_n)
            counter <= 0;
        else
            counter <= counter + 1;
    end

    wire _unused_ok_ = &{counter, pix_x, pix_y};

endmodule
