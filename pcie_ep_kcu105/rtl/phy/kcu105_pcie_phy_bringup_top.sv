`timescale 1ns/1ps
`default_nettype none

// K02 专用上板顶层：只执行一次 Receiver Detect，不包含任何 LTSSM 功能。
module kcu105_pcie_phy_bringup_top #(
    parameter integer DETECT_TIMEOUT_CYCLES = 16_000_000
) (
    input  wire       pcie_refclk_p,
    input  wire       pcie_refclk_n,
    input  wire       pcie_perst_n,
    input  wire       pcie_rxp,
    input  wire       pcie_rxn,
    output wire       pcie_txp,
    output wire       pcie_txn,
    output wire [7:0] led
);

    localparam logic [2:0] BUP_RESET       = 3'd0;
    localparam logic [2:0] BUP_SETTLE      = 3'd1;
    localparam logic [2:0] BUP_DETECT      = 3'd2;
    localparam logic [2:0] BUP_WAIT_STATUS = 3'd3;
    localparam logic [2:0] BUP_DONE        = 3'd4;
    localparam logic [2:0] BUP_TIMEOUT     = 3'd5;
    localparam logic [23:0] DETECT_TIMEOUT_LIMIT =
        DETECT_TIMEOUT_CYCLES[23:0] - 24'd1;

    wire        phy_coreclk;
    wire        phy_userclk;
    wire        phy_mcapclk;
    wire        phy_pclk;
    wire        pipe_rst_n;
    wire        core_rst_n;
    wire        phy_phystatus_rst;

    logic       phy_txdetectrx;
    logic [1:0] phy_powerdown;
    wire        phy_phystatus;
    wire [2:0]  phy_rxstatus;

    wire [31:0] phy_rxdata;
    wire [1:0]  phy_rxdatak;
    wire        phy_rxdata_valid;
    wire        phy_rxstart_block;
    wire [1:0]  phy_rxsync_header;
    wire        phy_rxvalid;
    wire        phy_rxelecidle;
    wire [5:0]  phy_txeq_fs;
    wire [5:0]  phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff;
    wire        phy_txeq_done;
    wire        phy_rxeq_preset_sel;
    wire [17:0] phy_rxeq_new_txcoeff;
    wire        phy_rxeq_adapt_done;
    wire        phy_rxeq_done;

    (* mark_debug = "true" *) logic [2:0] bup_state;
    (* mark_debug = "true" *) logic [2:0] detected_rxstatus;
    (* mark_debug = "true" *) logic       detect_done;
    (* mark_debug = "true" *) logic       receiver_present;
    (* mark_debug = "true" *) logic       detect_timeout;
    (* mark_debug = "true" *) logic       unexpected_status;
    logic [4:0]  settle_count;
    logic [23:0] timeout_count;
    logic [24:0] heartbeat_count;

    generate
        if ((DETECT_TIMEOUT_CYCLES < 1) ||
            (DETECT_TIMEOUT_CYCLES > 16_777_216)) begin : g_invalid_timeout
            initial $error("DETECT_TIMEOUT_CYCLES must be in [1, 16777216]");
        end
    endgenerate

    always_comb begin
        phy_powerdown  = 2'b10;
        phy_txdetectrx = 1'b0;
        if ((bup_state == BUP_DETECT) ||
            (bup_state == BUP_WAIT_STATUS)) begin
            phy_txdetectrx = 1'b1;
        end
    end

    always_ff @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            bup_state          <= BUP_RESET;
            settle_count       <= '0;
            timeout_count      <= '0;
            detected_rxstatus  <= '0;
            detect_done        <= 1'b0;
            receiver_present   <= 1'b0;
            detect_timeout     <= 1'b0;
            unexpected_status  <= 1'b0;
            heartbeat_count    <= '0;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;

            case (bup_state)
                BUP_RESET: begin
                    settle_count <= '0;
                    bup_state    <= BUP_SETTLE;
                end

                BUP_SETTLE: begin
                    if (settle_count == 5'd15) begin
                        bup_state <= BUP_DETECT;
                    end else begin
                        settle_count <= settle_count + 1'b1;
                    end
                end

                BUP_DETECT: begin
                    timeout_count <= '0;
                    bup_state     <= BUP_WAIT_STATUS;
                end

                BUP_WAIT_STATUS: begin
                    if (phy_phystatus) begin
                        detected_rxstatus <= phy_rxstatus;
                        detect_done       <= 1'b1;
                        receiver_present  <= (phy_rxstatus == 3'b011);
                        unexpected_status <= (phy_rxstatus != 3'b011);
                        bup_state         <= BUP_DONE;
                    end else if (timeout_count == DETECT_TIMEOUT_LIMIT) begin
                        detect_timeout <= 1'b1;
                        bup_state      <= BUP_TIMEOUT;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                BUP_DONE: begin
                    bup_state <= BUP_DONE;
                end

                BUP_TIMEOUT: begin
                    bup_state <= BUP_TIMEOUT;
                end

                default: begin
                    bup_state <= BUP_RESET;
                end
            endcase
        end
    end

    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = receiver_present;
    assign led[2] = detect_done;
    assign led[3] = pipe_rst_n;
    assign led[4] = core_rst_n;
    assign led[5] = detect_timeout;
    assign led[6] = unexpected_status;
    assign led[7] = heartbeat_count[24];

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p          (pcie_refclk_p),
        .pcie_refclk_n          (pcie_refclk_n),
        .pcie_perst_n           (pcie_perst_n),
        .pcie_rxp               (pcie_rxp),
        .pcie_rxn               (pcie_rxn),
        .pcie_txp               (pcie_txp),
        .pcie_txn               (pcie_txn),
        .phy_txdata             (32'b0),
        .phy_txdatak            (2'b0),
        .phy_txdata_valid       (1'b0),
        .phy_txstart_block      (1'b0),
        .phy_txsync_header      (2'b0),
        .phy_txdetectrx         (phy_txdetectrx),
        .phy_txelecidle         (1'b1),
        .phy_txcompliance       (1'b0),
        .phy_rxpolarity         (1'b0),
        .phy_powerdown          (phy_powerdown),
        .phy_rate               (2'b00),
        .phy_txmargin           (3'b0),
        .phy_txswing            (1'b0),
        .phy_txdeemph           (1'b0),
        .phy_txeq_ctrl          (2'b0),
        .phy_txeq_preset        (4'd4),
        .phy_txeq_coeff         (6'b0),
        .phy_rxeq_ctrl          (2'b0),
        .phy_rxeq_txpreset      (4'b0),
        .as_mac_in_detect       (1'b1),
        .as_cdr_hold_req        (1'b0),
        .phy_coreclk            (phy_coreclk),
        .phy_userclk            (phy_userclk),
        .phy_mcapclk            (phy_mcapclk),
        .phy_pclk               (phy_pclk),
        .pipe_rst_n             (pipe_rst_n),
        .core_rst_n             (core_rst_n),
        .phy_rxdata             (phy_rxdata),
        .phy_rxdatak            (phy_rxdatak),
        .phy_rxdata_valid       (phy_rxdata_valid),
        .phy_rxstart_block      (phy_rxstart_block),
        .phy_rxsync_header      (phy_rxsync_header),
        .phy_rxvalid            (phy_rxvalid),
        .phy_phystatus          (phy_phystatus),
        .phy_phystatus_rst      (phy_phystatus_rst),
        .phy_rxelecidle         (phy_rxelecidle),
        .phy_rxstatus           (phy_rxstatus),
        .phy_txeq_fs            (phy_txeq_fs),
        .phy_txeq_lf            (phy_txeq_lf),
        .phy_txeq_new_coeff     (phy_txeq_new_coeff),
        .phy_txeq_done          (phy_txeq_done),
        .phy_rxeq_preset_sel    (phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff   (phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done    (phy_rxeq_adapt_done),
        .phy_rxeq_done          (phy_rxeq_done)
    );

endmodule

`default_nettype wire
