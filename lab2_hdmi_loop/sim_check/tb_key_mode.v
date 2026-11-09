`timescale 1ns / 1ps
//=============================================================================
// tb_key_mode.v -- Task 4: key debounce + mode counter check
//   Clock at real 50MHz (20ns), DEB_MS=15 -> threshold 750,000 cycles (15ms)
//   Cases:
//     1) bouncing key (several <15ms glitches) counts as ONE press
//     2) long press (40ms) does not repeat
//     3) 6 presses: mode 0->1->2->3->0->1 (mod 4)
//     4) a 5ms pulse (< debounce window) is filtered out
//   NOTE: release must also be stable >= DEB_MS before the next press counts.
//=============================================================================
module tb_key_mode;

    localparam integer T_CLK      = 20;        // 20ns = 50MHz
    localparam integer DEB_MS     = 15;
    localparam integer RELEASE_MS = 20;        // must be >= DEB_MS

    reg  clk     = 0;
    reg  rst_n   = 0;
    reg  key_raw = 1'b1;                       // active low
    wire [1:0] mode_gray;
    wire [1:0] mode_bin;
    wire       key_press;
    integer    err = 0;
    integer    n_press = 0;

    always #(T_CLK/2) clk = ~clk;

    key_mode #(
        .CLK_FREQ       (50_000_000),
        .DEB_MS         (DEB_MS),
        .KEY_ACTIVE_LOW (1)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .key_raw    (key_raw),
        .mode_gray  (mode_gray),
        .mode_bin   (mode_bin),
        .key_press  (key_press)
    );

    always @(posedge clk) if (rst_n && key_press) n_press = n_press + 1;

    //-------------------------------------------------------------
    // helpers
    //-------------------------------------------------------------
    task wait_ms(input integer ms);
        integer k;
        begin
            for (k = 0; k < ms * 50_000; k = k + 1) @(posedge clk);
        end
    endtask

    // press with glitches (each glitch 200us), then hold low for hold_ms
    task press_with_bounce(input integer hold_ms);
        begin
            key_raw = 1'b0; #200_000;
            key_raw = 1'b1; #200_000;
            key_raw = 1'b0; #200_000;
            key_raw = 1'b1; #200_000;
            key_raw = 1'b0;                    // stable pressed
            wait_ms(hold_ms);
        end
    endtask

    // release with glitches, then hold high for RELEASE_MS
    task release_with_bounce;
        begin
            key_raw = 1'b1; #200_000;
            key_raw = 1'b0; #200_000;
            key_raw = 1'b1;                    // stable released
            wait_ms(RELEASE_MS);
        end
    endtask

    task check_mode(input [1:0] expect, input [127:0] tag);
        begin
            if (mode_bin !== expect) begin
                $display("  [FAIL] %0s : mode_bin=%0d expect %0d", tag, mode_bin, expect);
                err = err + 1;
            end else begin
                $display("  [ OK ] %0s : mode_bin=%0d (gray=%b)", tag, mode_bin, mode_gray);
            end
        end
    endtask

    //-------------------------------------------------------------
    // main
    //-------------------------------------------------------------
    initial begin
        $display("=== tb_key_mode start (debounce %0d ms @50MHz) ===", DEB_MS);
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);
        check_mode(2'd0, "after reset -> mode 0/passthru");

        // case 1: bouncing press counted once, and a LONG hold (60ms) must not repeat
        press_with_bounce(60);   check_mode(2'd1, "press#1 bounce+hold60ms -> 1 (once only)");
        release_with_bounce;

        // case 2: keep pressing, wraps at 4
        press_with_bounce(20);   check_mode(2'd2, "press#2 -> 2/smooth");  release_with_bounce;
        press_with_bounce(20);   check_mode(2'd3, "press#3 -> 3/sharp");   release_with_bounce;
        press_with_bounce(20);   check_mode(2'd0, "press#4 -> 0 (wrap)");  release_with_bounce;
        press_with_bounce(20);   check_mode(2'd1, "press#5 -> 1");         release_with_bounce;

        // case 3: short pulse (< debounce window) must be filtered
        key_raw = 1'b0; wait_ms(5);
        key_raw = 1'b1; wait_ms(RELEASE_MS);
        check_mode(2'd1, "5ms pulse filtered -> still 1");
        // summary
        $display("--------------------------------------------------");
        $display(" key_press count = %0d (expect 5)", n_press);
        if (n_press !== 5) begin
            $display(" [FAIL] press count mismatch");
            err = err + 1;
        end
        if (err == 0) $display(" >>> PASS: debounce / edge / mod-4 count all correct");
        else          $display(" >>> FAIL: %0d error(s)", err);
        $finish;
    end

endmodule
