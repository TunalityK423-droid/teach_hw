/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 *
 * Breakout V3
 * Destroy all bricks to win. Do not miss the ball.
 */
 
`default_nettype none
module tt_um_vga_example (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);

    //vga setup
    //generates pixel coordinates and display timing
    wire hsync;
    wire vsync;
    wire video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;
    wire [1:0] R;
    wire [1:0] G;
    wire [1:0] B;
    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
    assign uio_out = 0;
    assign uio_oe = 0;
    hvsync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    //game settings
    //change these constants to adjust sizes, speeds and brick layout
    localparam SCREEN_WIDTH = 640;
    localparam SCREEN_HEIGHT = 480;
    localparam PAD_WIDTH = 100;
    localparam PAD_HEIGHT = 10;
    localparam PAD_Y = 440;
    localparam PAD_SPEED = 8;
    localparam BALL_SIZE = 8;
    localparam BALL_SPEED_X = 6;
    localparam BALL_SPEED_Y = 6;
    localparam BRICK_WIDTH = 85;
    localparam BRICK_HEIGHT = 20;
    localparam BRICK_COLS = 6;
    localparam BRICK_ROWS = 3;
    localparam BRICK_X = 40;
    localparam BRICK_Y = 50;
    localparam BRICK_STEP_X = 95;
    localparam BRICK_STEP_Y = 30;

    //game controls
    //input 0 = right, 1 = left, 2 = restart
    wire inp_right = ui_in[0];
    wire inp_left = ui_in[1];
    wire inp_start = ui_in[2];

    //game object positions
    //stores current positions, directions, brick bits and game state
    reg [9:0] pad_x;
    reg [9:0] ball_x;
    reg [9:0] ball_y;
    //x: 0 = right, 1 = left; y: 0 = down, 1 = up
    reg ball_dx;
    reg ball_dy;
    //one bit per brick: 1 = exists, 0 = destroyed
    reg [BRICK_ROWS*BRICK_COLS-1:0] bricks;
    reg [BRICK_ROWS*BRICK_COLS-1:0] next_bricks;
    localparam PLAY = 0, WIN = 1, LOSE = 2;
    reg [1:0] game_state;
    reg missed_ball;

    //draw paddle and ball
    //checks if the current pixel is inside either rectangle
    wire paddle = (pix_x >= pad_x &&
                   pix_x < pad_x + PAD_WIDTH &&
                   pix_y >= PAD_Y &&
                   pix_y < PAD_Y + PAD_HEIGHT);
    wire ball = (pix_x >= ball_x &&
                 pix_x < ball_x + BALL_SIZE &&
                 pix_y >= ball_y &&
                 pix_y < ball_y + BALL_SIZE);

    //draw bricks
    //loops through each row and column and colors existing bricks
    reg [5:0] brick_color;
    integer draw_row;
    integer draw_col;
    integer draw_x;
    integer draw_y;
    always @(*) begin
        brick_color = 6'b000000;
        draw_x = 0;
        draw_y = 0;
        for (draw_row = 0; draw_row < BRICK_ROWS; draw_row = draw_row + 1) begin
            for (draw_col = 0; draw_col < BRICK_COLS; draw_col = draw_col + 1) begin
                //starting position of this brick
                draw_x = BRICK_X + draw_col * BRICK_STEP_X;
                draw_y = BRICK_Y + draw_row * BRICK_STEP_Y;
                //only draw the brick if its bit is 1
                if (bricks[draw_row * BRICK_COLS + draw_col] &&
                    pix_x >= draw_x &&
                    pix_x < draw_x + BRICK_WIDTH &&
                    pix_y >= draw_y &&
                    pix_y < draw_y + BRICK_HEIGHT) begin
                    //top red, middle yellow, bottom green
                    case (draw_row)
                        0: brick_color = 6'b110000;
                        1: brick_color = 6'b111100;
                        2: brick_color = 6'b001100;
                        default: begin end
                    endcase
                end
            end
        end
    end

    //set object colors
    //win and lose override the normal game colors
    reg [5:0] color;
    always @(*) begin
        color = 6'b000000;
        if (game_state == WIN)
            color = 6'b001100;
        else if (game_state == LOSE)
            color = 6'b110000;
        else if (paddle || ball)
            color = 6'b111111;
        else
            color = brick_color;
    end

    //vga color output
    //send rgb only while the current pixel is visible
    assign R = video_active ? color[5:4] : 2'b00;
    assign G = video_active ? color[3:2] : 2'b00;
    assign B = video_active ? color[1:0] : 2'b00;

    //frame timing
    //detect the rising edge of vsync to update once per frame
    reg old_vsync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            old_vsync <= 0;
        else
            old_vsync <= vsync;
    end
    wire frame_tick = vsync && !old_vsync;

    //calculate next paddle position
    //calculate movement first, then keep the paddle inside the screen
    integer next_pad_x;
    always @(*) begin
        next_pad_x = pad_x;
        //both inputs on means no movement
        if (inp_left && !inp_right)
            next_pad_x = next_pad_x - PAD_SPEED;
        else if (inp_right && !inp_left)
            next_pad_x = next_pad_x + PAD_SPEED;
        //stop at screen edges
        if (next_pad_x < 0)
            next_pad_x = 0;
        if (next_pad_x > SCREEN_WIDTH - PAD_WIDTH)
            next_pad_x = SCREEN_WIDTH - PAD_WIDTH;
    end

    //ball movement and collision
    //calculate the next position and correct it before saving
    //integers allow negative temporary positions near walls
    integer next_ball_x;
    integer next_ball_y;
    reg next_ball_dx;
    reg next_ball_dy;
    integer row;
    integer col;
    integer bx;
    integer by;
    reg hit_x;
    reg hit_y;
    always @(*) begin
        //start from current values and clear temporary flags
        next_ball_x = ball_x;
        next_ball_y = ball_y;
        next_ball_dx = ball_dx;
        next_ball_dy = ball_dy;
        hit_x = 0;
        hit_y = 0;
        bx = 0;
        by = 0;
        next_bricks = bricks;
        missed_ball = 0;

        //move the ball
        //add or subtract speed depending on direction
        if (ball_dx == 0)
            next_ball_x = next_ball_x + BALL_SPEED_X;
        else
            next_ball_x = next_ball_x - BALL_SPEED_X;
        if (ball_dy == 0)
            next_ball_y = next_ball_y + BALL_SPEED_Y;
        else
            next_ball_y = next_ball_y - BALL_SPEED_Y;

        //wall collision
        //bounce at left, right and top; reaching bottom means a miss
        if (next_ball_x < 0) begin
            next_ball_x = 0;
            next_ball_dx = 0;
        end
        if (next_ball_x > SCREEN_WIDTH - BALL_SIZE) begin
            next_ball_x = SCREEN_WIDTH - BALL_SIZE;
            next_ball_dx = 1;
        end
        if (next_ball_y < 0) begin
            next_ball_y = 0;
            next_ball_dy = 0;
        end
        if (next_ball_y >= SCREEN_HEIGHT - BALL_SIZE) begin
            next_ball_y = SCREEN_HEIGHT - BALL_SIZE;
            missed_ball = 1;
        end

        //paddle collision
        //bounce up only when a falling ball crosses the paddle top
        if (ball_dy == 0 &&
            ball_y + BALL_SIZE <= PAD_Y &&
            next_ball_y + BALL_SIZE >= PAD_Y &&
            next_ball_x + BALL_SIZE > next_pad_x &&
            next_ball_x < next_pad_x + PAD_WIDTH) begin
            next_ball_y = PAD_Y - BALL_SIZE;
            next_ball_dy = 1;
        end

        //brick collision
        //check rectangle overlap against every brick that still exists
        for (row = 0; row < BRICK_ROWS; row = row + 1) begin
            for (col = 0; col < BRICK_COLS; col = col + 1) begin
                bx = BRICK_X + col * BRICK_STEP_X;
                by = BRICK_Y + row * BRICK_STEP_Y;
                if (bricks[row * BRICK_COLS + col] &&
                    next_ball_x < bx + BRICK_WIDTH &&
                    next_ball_x + BALL_SIZE > bx &&
                    next_ball_y < by + BRICK_HEIGHT &&
                    next_ball_y + BALL_SIZE > by) begin

                    //destroy this brick
                    //set its bit to 0 so it disappears and cannot collide again
                    next_bricks[row * BRICK_COLS + col] = 0;
                    //use the old position to find which side was hit
                    if (ball_x + BALL_SIZE <= bx ||
                        ball_x >= bx + BRICK_WIDTH)
                        hit_x = 1;
                    if (ball_y + BALL_SIZE <= by ||
                        ball_y >= by + BRICK_HEIGHT)
                        hit_y = 1;
                end
            end
        end

        //bounce left or right if ball hit the side
        if (hit_x) begin
            next_ball_x = ball_x;
            next_ball_dx = !ball_dx;
        end

        //bounce up or down if ball hit the top or bottom
        if (hit_y) begin
            next_ball_y = ball_y;
            next_ball_dy = !ball_dy;
        end
    end

    //update game positions
    //save calculated values on the clock when frame_tick is active
    always @(posedge clk or negedge rst_n) begin

        //reset the game
        //restore starting positions, directions and all brick bits
        if (!rst_n) begin
            pad_x <= 270;
            ball_x <= 316;
            ball_y <= 300;
            ball_dx <= 0;
            ball_dy <= 1;
            bricks <= {BRICK_ROWS*BRICK_COLS{1'b1}};
            game_state <= PLAY;
        end

        //restart button
        //same starting values; turn restart off to continue
        else if (inp_start) begin
            pad_x <= 270;
            ball_x <= 316;
            ball_y <= 300;
            ball_dx <= 0;
            ball_dy <= 1;
            bricks <= {BRICK_ROWS*BRICK_COLS{1'b1}};
            game_state <= PLAY;
        end

        //update positions once per frame
        //only move objects while the game state is play
        else if (frame_tick && game_state == PLAY) begin
            pad_x <= next_pad_x;
            ball_x <= next_ball_x;
            ball_y <= next_ball_y;
            ball_dx <= next_ball_dx;
            ball_dy <= next_ball_dy;
            bricks <= next_bricks;

            //win/lose condition
            //missed ball = lose, all brick bits zero = win
            if (missed_ball)
                game_state <= LOSE;
            else if (next_bricks == 0)
                game_state <= WIN;
        end
    end

    //unused inputs
    //mark unused pins to help avoid warnings
    wire _unused_ok = &{ena, ui_in[7:3], uio_in};
endmodule
