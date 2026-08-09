`timescale 1ns/1ps
`default_nettype none

// K10：4 KiB、32-bit、单Outstanding Demo AXI4-Lite Slave。
module demo_axil_slave #(
    parameter [31:0] VERSION = 32'h0001_0000
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  s_axil_awaddr,
    input  wire         s_axil_awvalid,
    output wire         s_axil_awready,
    input  wire [31:0]  s_axil_wdata,
    input  wire [3:0]   s_axil_wstrb,
    input  wire         s_axil_wvalid,
    output wire         s_axil_wready,
    output reg  [1:0]   s_axil_bresp,
    output reg          s_axil_bvalid,
    input  wire         s_axil_bready,

    input  wire [31:0]  s_axil_araddr,
    input  wire         s_axil_arvalid,
    output wire         s_axil_arready,
    output reg  [31:0]  s_axil_rdata,
    output reg  [1:0]   s_axil_rresp,
    output reg          s_axil_rvalid,
    input  wire         s_axil_rready,

    input  wire         link_up,
    input  wire [1:0]   link_speed,
    input  wire [5:0]   ltssm_state,
    input  wire         dll_active,
    input  wire [3:0]   dll_state,

    input  wire [31:0]  rx_bad_symbol_count,
    input  wire [31:0]  ltssm_retrain_count,
    input  wire [31:0]  dll_lcrc_error_count,
    input  wire [31:0]  dll_nak_count,
    input  wire [31:0]  dll_replay_count,
    input  wire [31:0]  dll_replay_timeout_count,
    input  wire [31:0]  tl_malformed_count,
    input  wire [31:0]  tl_unsupported_count,
    input  wire [31:0]  bar_ur_count,
    input  wire [31:0]  bar_ca_count,
    input  wire [31:0]  bar_axi_error_count,
    input  wire [31:0]  bar_payload_error_count
);
    localparam [1:0] AXI_OKAY   = 2'b00;
    localparam [1:0] AXI_DECERR = 2'b11;

    reg [31:0] scratch [0:47];
    (* ram_style = "block" *) reg [31:0] test_ram [0:1023];

    reg        aw_pending;
    reg [31:0] awaddr_reg;
    reg        w_pending;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;
    reg        read_pending;
    reg [31:0] araddr_reg;
    reg [31:0] ram_read_data;

    integer reset_index;

    wire write_commit = aw_pending && w_pending && !s_axil_bvalid;
    wire write_address_valid = (awaddr_reg[31:12] == 20'd0) &&
                               (awaddr_reg[1:0] == 2'b00);
    wire write_scratch = write_address_valid &&
                         (awaddr_reg[11:0] >= 12'h040) &&
                         (awaddr_reg[11:0] < 12'h100);
    wire write_ram = write_address_valid && (awaddr_reg[11:0] >= 12'h100);
    wire [5:0] scratch_index = awaddr_reg[7:2] - 6'd16;
    wire [9:0] ram_index = awaddr_reg[11:2] - 10'd64;

    assign s_axil_awready = rst_n && !aw_pending && !s_axil_bvalid;
    assign s_axil_wready  = rst_n && !w_pending && !s_axil_bvalid;
    assign s_axil_arready = rst_n && !read_pending && !s_axil_rvalid;

    // RAM阵列故意不复位，保持Byte-write RAM推断条件。
    always @(posedge clk) begin
        if (write_commit && write_ram) begin
            if (wstrb_reg[0]) test_ram[ram_index][7:0] <= wdata_reg[7:0];
            if (wstrb_reg[1]) test_ram[ram_index][15:8] <= wdata_reg[15:8];
            if (wstrb_reg[2]) test_ram[ram_index][23:16] <= wdata_reg[23:16];
            if (wstrb_reg[3]) test_ram[ram_index][31:24] <= wdata_reg[31:24];
        end
        if (s_axil_arvalid && s_axil_arready &&
            (s_axil_araddr[31:12] == 20'd0) &&
            (s_axil_araddr[1:0] == 2'b00) &&
            (s_axil_araddr[11:0] >= 12'h100))
            ram_read_data <= test_ram[s_axil_araddr[11:2] - 10'd64];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pending   <= 1'b0;
            awaddr_reg   <= 32'd0;
            w_pending    <= 1'b0;
            wdata_reg    <= 32'd0;
            wstrb_reg    <= 4'd0;
            read_pending <= 1'b0;
            araddr_reg   <= 32'd0;
            s_axil_bresp <= AXI_OKAY;
            s_axil_bvalid <= 1'b0;
            s_axil_rdata <= 32'd0;
            s_axil_rresp <= AXI_OKAY;
            s_axil_rvalid <= 1'b0;
            for (reset_index = 0; reset_index < 48;
                 reset_index = reset_index + 1)
                scratch[reset_index] <= 32'd0;
        end else begin
            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;

            if (s_axil_awvalid && s_axil_awready) begin
                aw_pending <= 1'b1;
                awaddr_reg <= s_axil_awaddr;
            end
            if (s_axil_wvalid && s_axil_wready) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axil_wdata;
                wstrb_reg <= s_axil_wstrb;
            end

            if (write_commit) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp <= write_address_valid ? AXI_OKAY : AXI_DECERR;
                if (write_scratch) begin
                    if (wstrb_reg[0])
                        scratch[scratch_index][7:0] <= wdata_reg[7:0];
                    if (wstrb_reg[1])
                        scratch[scratch_index][15:8] <= wdata_reg[15:8];
                    if (wstrb_reg[2])
                        scratch[scratch_index][23:16] <= wdata_reg[23:16];
                    if (wstrb_reg[3])
                        scratch[scratch_index][31:24] <= wdata_reg[31:24];
                end
            end

            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;

            if (s_axil_arvalid && s_axil_arready) begin
                read_pending <= 1'b1;
                araddr_reg <= s_axil_araddr;
            end

            if (read_pending) begin
                read_pending <= 1'b0;
                s_axil_rvalid <= 1'b1;
                if ((araddr_reg[31:12] != 20'd0) ||
                    (araddr_reg[1:0] != 2'b00)) begin
                    s_axil_rdata <= 32'd0;
                    s_axil_rresp <= AXI_DECERR;
                end else begin
                    s_axil_rresp <= AXI_OKAY;
                    case (araddr_reg[11:2])
                        10'h000: s_axil_rdata <= 32'h5043_4945;
                        10'h001: s_axil_rdata <= VERSION;
                        10'h002: s_axil_rdata <=
                            {18'd0, ltssm_state, 5'd0, link_speed, link_up};
                        10'h003: s_axil_rdata <=
                            {24'd0, dll_state, 3'd0, dll_active};
                        10'h004: s_axil_rdata <= rx_bad_symbol_count;
                        10'h005: s_axil_rdata <= ltssm_retrain_count;
                        10'h006: s_axil_rdata <= dll_lcrc_error_count;
                        10'h007: s_axil_rdata <= dll_nak_count;
                        10'h008: s_axil_rdata <= dll_replay_count;
                        10'h009: s_axil_rdata <= dll_replay_timeout_count;
                        10'h00a: s_axil_rdata <= tl_malformed_count;
                        10'h00b: s_axil_rdata <= tl_unsupported_count;
                        10'h00c: s_axil_rdata <= bar_ur_count;
                        10'h00d: s_axil_rdata <= bar_ca_count;
                        10'h00e: s_axil_rdata <= bar_axi_error_count;
                        10'h00f: s_axil_rdata <= bar_payload_error_count;
                        default: begin
                            if (araddr_reg[11:0] < 12'h100)
                                s_axil_rdata <= scratch[araddr_reg[7:2] - 6'd16];
                            else
                                s_axil_rdata <= ram_read_data;
                        end
                    endcase
                end
            end
        end
    end
endmodule

`default_nettype wire
