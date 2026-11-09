// lab3_nn_top.v —— 全链路：UART 解帧 -> img_buf -> HLS 推理核 -> argmax -> 数码管/LED -> 回传
// HLS 核以 IP 形式例化（module_name = nn_top_0，见 vivado/build_nn.tcl）
module lab3_nn_top (
    input  clk,
    input  rst_n,
    input  uart_rxd,
    output uart_txd,
    output [3:0] led,
    output [7:0] seg_led,
    output [5:0] seg_sel
);
    // ---------------- UART RX ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx #(.CLK_FREQ(50_000_000), .BAUD(1000000)) u_rx (
        .clk(clk), .rst_n(rst_n), .rxd(uart_rxd),
        .data(rx_data), .valid(rx_valid)
    );

    // ---------------- frame decode ----------------
    wire [9:0] img_waddr;
    wire [7:0] img_wdata;
    wire       img_we;
    wire       frame_ok;
    wire [7:0] seq_out;
    frame_decode u_fd (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .img_waddr(img_waddr), .img_wdata(img_wdata), .img_we(img_we),
        .frame_ok(frame_ok), .seq_out(seq_out)
    );

    // ---------------- img BRAM（写：解帧；读：NN） ----------------
    reg [7:0] img_mem [0:783];
    always @(posedge clk) begin
        if (img_we) img_mem[img_waddr] <= img_wdata;
    end

    // ---------------- NN IP ----------------
    reg         nn_start;
    wire        nn_done;
    wire        nn_idle;
    wire        nn_ready;
    wire [9:0]  nn_img_addr;
    wire        nn_img_ce;
    wire [7:0]  nn_img_q;
    wire [3:0]  nn_lg_addr;
    wire        nn_lg_ce;
    wire        nn_lg_we;
    wire [31:0] nn_lg_d0;

    reg  [7:0]  nn_q_d;
    always @(posedge clk) begin
        if (nn_img_ce) nn_q_d <= img_mem[nn_img_addr];
    end
    assign nn_img_q = nn_q_d;

    nn_top_0 u_nn (
        .ap_clk(clk),
        .ap_rst(~rst_n),
        .ap_start(nn_start),
        .ap_done(nn_done),
        .ap_idle(nn_idle),
        .ap_ready(nn_ready),
        .img_V_address0(nn_img_addr),
        .img_V_ce0(nn_img_ce),
        .img_V_q0(nn_img_q),
        .logits_address0(nn_lg_addr),
        .logits_ce0(nn_lg_ce),
        .logits_we0(nn_lg_we),
        .logits_d0(nn_lg_d0)
    );

    // ---------------- logit BRAM ----------------
    reg [31:0] logit_mem [0:9];
    always @(posedge clk) begin
        if (nn_lg_we) logit_mem[nn_lg_addr] <= nn_lg_d0;
    end

    // ---------------- FSM: start -> wait done -> argmax -> 显示/回传 ----------------
    localparam S_IDLE = 2'd0, S_INF = 2'd1, S_READ = 2'd2, S_DONE = 2'd3;
    reg [1:0]  st;
    reg [3:0]  rd_cnt;
    reg [31:0] max_val;
    reg [3:0]  max_idx;
    reg [3:0]  digit;
    reg        tx_start;
    reg [7:0]  tx_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; nn_start <= 1'b0; rd_cnt <= 0;
            max_val <= 32'h80000000; max_idx <= 0; digit <= 4'hF;
            tx_start <= 1'b0; tx_data <= 8'h00;
        end else begin
            tx_start <= 1'b0;
            nn_start <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (frame_ok) begin
                        nn_start <= 1'b1;
                        st       <= S_INF;
                    end
                end
                S_INF: begin
                    if (nn_done) begin
                        rd_cnt  <= 4'd0;
                        max_val <= 32'h80000000;
                        max_idx <= 4'd0;
                        st      <= S_READ;
                    end
                end
                S_READ: begin
                    if ($signed(logit_mem[rd_cnt]) > $signed(max_val)) begin
                        max_val <= logit_mem[rd_cnt];
                        max_idx <= rd_cnt;
                    end
                    if (rd_cnt == 4'd9) st <= S_DONE;
                    else                rd_cnt <= rd_cnt + 1'b1;
                end
                S_DONE: begin
                    digit    <= max_idx;
                    tx_data  <= {4'b0000, max_idx};
                    tx_start <= 1'b1;
                    st       <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    // ---------------- 回传 + 显示 ----------------
    uart_tx #(.CLK_FREQ(50_000_000), .BAUD(1000000)) u_tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .tx_data(tx_data),
        .txd(uart_txd), .busy()
    );

    assign led = digit;

    seg_display u_seg (
        .clk(clk), .rst_n(rst_n), .digit(digit),
        .seg_led(seg_led), .seg_sel(seg_sel)
    );
endmodule
