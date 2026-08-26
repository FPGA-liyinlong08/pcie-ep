`timescale 1ns/1ps
`default_nettype none

// Observation-only Root-Port-directed Recovery timing recorder. Timestamps
// remain on-chip; a compact 64-bit row stream is exposed to the ILA so this
// diagnostic cannot add a large timing-critical fanout.
module pcie_recovery_timing_recorder #(
    parameter integer COUNTER_WIDTH = 20
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   semantic_retrain_valid,
    input  wire                   partner_retrain_valid,
    input  wire                   speed_retrain_accept,
    input  wire [5:0]             ltssm_state,
    input  wire                   ltssm_speed_ready,
    input  wire [2:0]             speed_state,
    input  wire [3:0]             rate_state,
    input  wire [1:0]             phy_rate,
    input  wire                   os_ts1_valid,
    input  wire                   os_ts2_valid,
    input  wire                   phy_rxelecidle,
    input  wire                   phy_rxvalid,
    input  wire                   qpll1lock,
    input  wire                   pcierateqpllreset,
    input  wire                   pcierateidle,
    input  wire                   phy_phystatus,
    output wire [63:0]            record_bus,
    output wire                   dump_active
);
    localparam [5:0] LTSSM_RCVRLOCK = 6'd11;
    localparam [5:0] LTSSM_RCVRCFG  = 6'd12;
    localparam [2:0] SPEED_RATE_REQUEST = 3'd2;
    localparam [3:0] RATE_RELEASE = 4'd1;
    localparam [3:0] RATE_GOLDEN_GAP = 4'd2;
    localparam [COUNTER_WIDTH-1:0] PHY_DONE_WAIT = 20'd20000;
    localparam [COUNTER_WIDTH-1:0] DUMP_TIMEOUT = 20'd100000;

    reg [COUNTER_WIDTH-1:0] elapsed;
    reg [19:0] valid;
    reg active, dump_pending, dump_active_r;
    reg [4:0] dump_index;
    reg [19:0] dump_valid;
    reg [5:0] ltssm_state_d;
    reg [2:0] speed_state_d;
    reg [3:0] rate_state_d;
    reg [1:0] phy_rate_d;
    reg phy_rxelecidle_d, phy_rxvalid_d, qpll1lock_d;
    reg pcierateqpllreset_d, pcierateidle_d, phy_phystatus_d;
    // T0..T8, R0..R3, G0..G6.
    reg [COUNTER_WIDTH-1:0] stamp [0:19];

    wire phy_rate_gen3_rise = (phy_rate == 2'b10) && (phy_rate_d != 2'b10);
    wire start_evt = !active && !dump_active_r && !dump_pending &&
                     (semantic_retrain_valid || phy_rate_gen3_rise);
    wire finish_evt = active &&
        ((valid[8] && (valid[19] || (elapsed >= (stamp[8] + PHY_DONE_WAIT)))) ||
         (elapsed >= DUMP_TIMEOUT));

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            elapsed <= '0; valid <= 20'd0; active <= 1'b0;
            dump_pending <= 1'b0; dump_active_r <= 1'b0;
            dump_index <= 5'd0; dump_valid <= 20'd0;
            ltssm_state_d <= 6'd0; speed_state_d <= 3'd0;
            rate_state_d <= 4'd0; phy_rate_d <= 2'b00;
            phy_rxelecidle_d <= 1'b0; phy_rxvalid_d <= 1'b0;
            qpll1lock_d <= 1'b0; pcierateqpllreset_d <= 1'b0;
            pcierateidle_d <= 1'b0; phy_phystatus_d <= 1'b0;
            for (i = 0; i < 20; i = i + 1) stamp[i] <= '0;
        end else begin
            ltssm_state_d <= ltssm_state; speed_state_d <= speed_state;
            rate_state_d <= rate_state; phy_rate_d <= phy_rate;
            phy_rxelecidle_d <= phy_rxelecidle; phy_rxvalid_d <= phy_rxvalid;
            qpll1lock_d <= qpll1lock;
            pcierateqpllreset_d <= pcierateqpllreset;
            pcierateidle_d <= pcierateidle; phy_phystatus_d <= phy_phystatus;

            if (dump_active_r) begin
                if (dump_index == 5'd19) begin
                    dump_active_r <= 1'b0; dump_index <= 5'd0;
                end else dump_index <= dump_index + 1'b1;
            end else if (dump_pending) begin
                // Delay one cycle so the final PhyStatus event is included.
                dump_pending <= 1'b0; dump_active_r <= 1'b1;
                dump_index <= 5'd0; dump_valid <= valid;
            end else if (start_evt) begin
                active <= 1'b1; elapsed <= '0; valid <= 20'd0;
                if (partner_retrain_valid) begin valid[0] <= 1'b1; stamp[0] <= '0; end
                if (speed_retrain_accept) begin valid[1] <= 1'b1; stamp[1] <= '0; end
                if (phy_rate_gen3_rise) begin valid[8] <= 1'b1; stamp[8] <= '0; end
                if (os_ts1_valid) begin valid[9] <= 1'b1; stamp[9] <= '0; end
                if (os_ts2_valid) begin valid[10] <= 1'b1; stamp[10] <= '0; end
            end else if (active) begin
                if (!valid[0] && partner_retrain_valid) begin valid[0] <= 1'b1; stamp[0] <= elapsed; end
                if (!valid[1] && speed_retrain_accept) begin valid[1] <= 1'b1; stamp[1] <= elapsed; end
                if (!valid[2] && ltssm_state_d != LTSSM_RCVRLOCK && ltssm_state == LTSSM_RCVRLOCK) begin valid[2] <= 1'b1; stamp[2] <= elapsed; end
                if (!valid[3] && ltssm_state_d != LTSSM_RCVRCFG && ltssm_state == LTSSM_RCVRCFG) begin valid[3] <= 1'b1; stamp[3] <= elapsed; end
                if (!valid[4] && ltssm_speed_ready) begin valid[4] <= 1'b1; stamp[4] <= elapsed; end
                if (!valid[5] && speed_state_d != SPEED_RATE_REQUEST && speed_state == SPEED_RATE_REQUEST) begin valid[5] <= 1'b1; stamp[5] <= elapsed; end
                if (!valid[6] && rate_state_d != RATE_RELEASE && rate_state == RATE_RELEASE) begin valid[6] <= 1'b1; stamp[6] <= elapsed; end
                if (!valid[7] && rate_state_d != RATE_GOLDEN_GAP && rate_state == RATE_GOLDEN_GAP) begin valid[7] <= 1'b1; stamp[7] <= elapsed; end
                if (!valid[8] && phy_rate_gen3_rise) begin valid[8] <= 1'b1; stamp[8] <= elapsed; end
                if (os_ts1_valid && phy_rate != 2'b10) begin valid[9] <= 1'b1; stamp[9] <= elapsed; end
                if (os_ts2_valid && phy_rate != 2'b10) begin valid[10] <= 1'b1; stamp[10] <= elapsed; end
                if (!valid[11] && !phy_rxelecidle_d && phy_rxelecidle) begin valid[11] <= 1'b1; stamp[11] <= elapsed; end
                if (!valid[12] && phy_rxvalid_d && !phy_rxvalid) begin valid[12] <= 1'b1; stamp[12] <= elapsed; end
                if (!valid[13] && qpll1lock_d && !qpll1lock) begin valid[13] <= 1'b1; stamp[13] <= elapsed; end
                if (!valid[14] && !pcierateqpllreset_d && pcierateqpllreset) begin valid[14] <= 1'b1; stamp[14] <= elapsed; end
                if (!valid[15] && pcierateqpllreset_d && !pcierateqpllreset) begin valid[15] <= 1'b1; stamp[15] <= elapsed; end
                if (!valid[16] && !qpll1lock_d && qpll1lock) begin valid[16] <= 1'b1; stamp[16] <= elapsed; end
                if (!valid[17] && pcierateidle_d && !pcierateidle) begin valid[17] <= 1'b1; stamp[17] <= elapsed; end
                if (!valid[18] && !pcierateidle_d && pcierateidle) begin valid[18] <= 1'b1; stamp[18] <= elapsed; end
                if (!valid[19] && !phy_phystatus_d && phy_phystatus) begin valid[19] <= 1'b1; stamp[19] <= elapsed; end
                if (finish_evt) begin active <= 1'b0; dump_pending <= 1'b1; end
                else if (!(&elapsed)) elapsed <= elapsed + 1'b1;
            end
        end
    end

    reg [COUNTER_WIDTH-1:0] selected_stamp;
    always @* begin
        selected_stamp = '0;
        case (dump_index)
            5'd0: selected_stamp = stamp[0];   5'd1: selected_stamp = stamp[1];
            5'd2: selected_stamp = stamp[2];   5'd3: selected_stamp = stamp[3];
            5'd4: selected_stamp = stamp[4];   5'd5: selected_stamp = stamp[5];
            5'd6: selected_stamp = stamp[6];   5'd7: selected_stamp = stamp[7];
            5'd8: selected_stamp = stamp[8];   5'd9: selected_stamp = stamp[9];
            5'd10: selected_stamp = stamp[10]; 5'd11: selected_stamp = stamp[11];
            5'd12: selected_stamp = stamp[12]; 5'd13: selected_stamp = stamp[13];
            5'd14: selected_stamp = stamp[14]; 5'd15: selected_stamp = stamp[15];
            5'd16: selected_stamp = stamp[16]; 5'd17: selected_stamp = stamp[17];
            5'd18: selected_stamp = stamp[18]; 5'd19: selected_stamp = stamp[19];
            default: selected_stamp = '0;
        endcase
    end

    // [19:0] timestamp, [24:20] event index, [25] stream valid,
    // [45:26] valid-event snapshot, [63:46] reserved.
    assign dump_active = dump_active_r;
    assign record_bus = {{18{1'b0}}, dump_valid, dump_active_r,
                         dump_index, selected_stamp};
endmodule

`default_nettype wire
