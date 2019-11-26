//============================================================================
//
//  Screen +90/-90 deg. rotation
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

//
// Output timings are incompatible with any TV/VGA mode.
// The output is supposed to be send to scaler input.
//
module screen_rotate #(parameter WIDTH=320, HEIGHT=240, DEPTH=8, MARGIN=4, CCW=0)
(
	input              clk,
	input              ce,

	input  [DEPTH-1:0] video_in,
	input              hblank,
	input              vblank,

	input              ce_out,
	output [DEPTH-1:0] video_out,
	output reg         hsync,
	output reg         vsync,
	output reg         hblank_out,
	output reg         vblank_out
);

localparam bufsize = WIDTH*HEIGHT;
localparam memsize = bufsize*2;
localparam aw = $clog2(memsize); // resolutions up to ~ 512x256

reg [aw-1:0] addr_in, addr_out;
reg we_in;
reg buff = 0;

(* ramstyle="no_rw_check" *) reg [DEPTH-1:0] ram[memsize];
always @ (posedge clk) if (en_we) ram[addr_in] <= video_in;
always @ (posedge clk) out <= ram[addr_out];

reg [DEPTH-1:0] out; 
reg [DEPTH-1:0] vout;

assign video_out = vout;

wire en_we = ce & ~blank & en_x & en_y;
wire en_x = (xpos<WIDTH);
wire en_y = (ypos<HEIGHT);
integer xpos, ypos;

wire blank = hblank | vblank;
always @(posedge clk) begin
	reg old_blank, old_vblank;
	reg [aw-1:0] addr_row;

	if(en_we) begin
		addr_in <= CCW ? addr_in-HEIGHT[aw-1:0] : addr_in+HEIGHT[aw-1:0];
		xpos <= xpos + 1;
	end

	old_blank <= blank;
	old_vblank <= vblank;
	if(~old_blank & blank) begin
		xpos <= 0;
		ypos <= ypos + 1;
		addr_in  <= CCW ? addr_row + 1'd1 : addr_row - 1'd1;
		addr_row <= CCW ? addr_row + 1'd1 : addr_row - 1'd1;
	end

	if(~old_vblank & vblank) begin
		if(buff) begin
			addr_in  <= CCW ? bufsize[aw-1:0]-HEIGHT[aw-1:0] : HEIGHT[aw-1:0]-1'd1;
			addr_row <= CCW ? bufsize[aw-1:0]-HEIGHT[aw-1:0] : HEIGHT[aw-1:0]-1'd1;
		end else begin
			addr_in  <= CCW ? bufsize[aw-1:0]+bufsize[aw-1:0]-HEIGHT[aw-1:0] : bufsize[aw-1:0]+HEIGHT[aw-1:0]-1'd1;
			addr_row <= CCW ? bufsize[aw-1:0]+bufsize[aw-1:0]-HEIGHT[aw-1:0] : bufsize[aw-1:0]+HEIGHT[aw-1:0]-1'd1;
		end
		buff <= ~buff;
		ypos <= 0;
		xpos <= 0;
	end
end

always @(posedge clk) begin
	reg old_buff;
	reg hs;
	reg ced;

	integer vbcnt;
	integer xposo, yposo, xposd, yposd;
	
	ced <= 0;
	if(ce_out) begin
		ced <= 1;

		xposd <= xposo;
		yposd <= yposo;

		if(xposo == (HEIGHT + 8))  hsync <= 1;
		if(xposo == (HEIGHT + 10)) hsync <= 0;

		if((yposo>=MARGIN) && (yposo<WIDTH+MARGIN)) begin
			if(xposo < HEIGHT) addr_out <= addr_out + 1'd1;
		end

		xposo <= xposo + 1;
		if(xposo > (HEIGHT + 16)) begin
			xposo  <= 0;
			
			if(yposo >= (WIDTH+MARGIN+MARGIN)) begin
				vblank_out <= 1;
				vbcnt <= vbcnt + 1;
				if(vbcnt == 10	) vsync <= 1;
				if(vbcnt == 12) vsync <= 0;
			end
			else yposo <= yposo + 1;
			
			old_buff <= buff;
			if(old_buff != buff) begin
				addr_out <= buff ? {aw{1'b0}} : bufsize[aw-1:0];
				yposo <= 0;
				vsync <= 0;
				vbcnt <= 0;
				vblank_out <= 0;
			end
		end
	end
	
	if(ced) begin
		if((yposd<MARGIN) || (yposd>=WIDTH+MARGIN)) begin
			vout <= 0;
		end else begin
			vout <= out;
		end
		if(xposd == 0)       hblank_out <= 0;
		if(xposd == HEIGHT)  hblank_out <= 1;
	end
end

endmodule

//////////////////////////////////////////////////////////

// DW:
//  6 : 2R 2G 2B
//  8 : 3R 3G 2B
//  9 : 3R 3G 3B
// 12 : 4R 4G 4B

module arcade_rotate_fx #(parameter WIDTH=320, HEIGHT=240, DW=8, CCW=0, GAMMA=1)
(
	input         clk_video,
	input         ce_pix,

	input[DW-1:0] RGB_in,
	input         HBlank,
	input         VBlank,
	input         HSync,
	input         VSync,

	output        VGA_CLK,
	output reg    VGA_CE,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,

	output        HDMI_CLK,
	output        HDMI_CE,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,
	output  [1:0] HDMI_SL,
	
	input   [2:0] fx,
	input         forced_scandoubler,
	input         no_rotate,
	inout  [21:0] gamma_bus
);

assign VGA_CLK = clk_video;
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = ~(HBlank | VBlank);

wire hs_fix,vs_fix;
sync_fix sync_v(VGA_CLK, HSync, hs_fix);
sync_fix sync_h(VGA_CLK, VSync, vs_fix);

reg hs,vs;
always @(posedge VGA_CLK) begin
	reg old_ce;
	old_ce <= ce_pix;
	VGA_CE <= 0;
	if(~old_ce & ce_pix) begin
		VGA_CE <= 1;
		hs <= hs_fix;
		if(~hs & hs_fix) vs <= vs_fix;
	end
end

generate
	if(DW == 6) begin
		assign VGA_R = {RGB_in[5:4],RGB_in[5:4],RGB_in[5:4],RGB_in[5:4]};
		assign VGA_G = {RGB_in[3:2],RGB_in[3:2],RGB_in[3:2],RGB_in[3:2]};
		assign VGA_B = {RGB_in[1:0],RGB_in[1:0],RGB_in[1:0],RGB_in[1:0]};
	end
	else if(DW == 8) begin
		assign VGA_R = {RGB_in[7:5],RGB_in[7:5],RGB_in[7:6]};
		assign VGA_G = {RGB_in[4:2],RGB_in[4:2],RGB_in[4:3]};
		assign VGA_B = {RGB_in[1:0],RGB_in[1:0],RGB_in[1:0],RGB_in[1:0]};
	end
	else if(DW == 9) begin
		assign VGA_R = {RGB_in[8:6],RGB_in[8:6],RGB_in[8:7]};
		assign VGA_G = {RGB_in[5:3],RGB_in[5:3],RGB_in[5:4]};
		assign VGA_B = {RGB_in[2:0],RGB_in[2:0],RGB_in[2:1]};
	end
	else begin
		assign VGA_R = {RGB_in[11:8],RGB_in[11:8]};
		assign VGA_G = {RGB_in[7:4],RGB_in[7:4]};
		assign VGA_B = {RGB_in[3:0],RGB_in[3:0]};
	end
endgenerate

wire [DW-1:0] RGB_out;
wire rhs,rvs,rhblank,rvblank;

screen_rotate #(WIDTH,HEIGHT,DW,4,CCW) rotator
(
	.clk(VGA_CLK),
	.ce(VGA_CE),

	.video_in(RGB_in),
	.hblank(HBlank),
	.vblank(VBlank),

	.ce_out(VGA_CE | (~scandoubler & ~gamma_bus[19])),
	.video_out(RGB_out),
	.hsync(rhs),
	.vsync(rvs),
	.hblank_out(rhblank),
	.vblank_out(rvblank)
);

wire [3:0] Rr,Gr,Br;

generate
	if(DW == 6) begin
		assign Rr = {RGB_out[5:4],RGB_out[5:4]};
		assign Gr = {RGB_out[3:2],RGB_out[3:2]};
		assign Br = {RGB_out[1:0],RGB_out[1:0]};
	end
	else if(DW == 8) begin
		assign Rr = {RGB_out[7:5],RGB_out[7]};
		assign Gr = {RGB_out[4:2],RGB_out[4]};
		assign Br = {RGB_out[1:0],RGB_out[1:0]};
	end
	else if(DW == 9) begin
		assign Rr = {RGB_out[8:6],RGB_out[8]};
		assign Gr = {RGB_out[5:3],RGB_out[5]};
		assign Br = {RGB_out[2:0],RGB_out[2]};
	end
	else begin
		assign Rr = RGB_out[11:8];
		assign Gr = RGB_out[7:4];
		assign Br = RGB_out[3:0];
	end
endgenerate

assign HDMI_CLK = VGA_CLK;
assign HDMI_SL  = no_rotate ? 2'd0 : sl[1:0];
wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;
wire scandoubler = fx || forced_scandoubler;

video_mixer #(WIDTH+4, 1, GAMMA) video_mixer
(
	.clk_vid(HDMI_CLK),
	.ce_pix(VGA_CE | (~scandoubler & ~gamma_bus[19])),
	.ce_pix_out(HDMI_CE),

	.scandoubler(scandoubler),
	.hq2x(fx==1),
	.gamma_bus(gamma_bus),

	.R(no_rotate ? VGA_R[7:4] : Rr),
	.G(no_rotate ? VGA_G[7:4] : Gr),
	.B(no_rotate ? VGA_B[7:4] : Br),

	.HSync (no_rotate ? hs : rhs),
	.VSync (no_rotate ? vs : rvs),
	.HBlank(no_rotate ? HBlank : rhblank),
	.VBlank(no_rotate ? VBlank : rvblank),

	.VGA_R(HDMI_R),
	.VGA_G(HDMI_G),
	.VGA_B(HDMI_B),
	.VGA_VS(HDMI_VS),
	.VGA_HS(HDMI_HS),
	.VGA_DE(HDMI_DE)
);

endmodule

//////////////////////////////////////////////////////////

// DW:
//  6 : 2R 2G 2B
//  8 : 3R 3G 2B
//  9 : 3R 3G 3B
// 12 : 4R 4G 4B

module arcade_fx #(parameter WIDTH=320, DW=8, GAMMA=1)
(
	input         clk_video,
	input         ce_pix,

	input[DW-1:0] RGB_in,
	input         HBlank,
	input         VBlank,
	input         HSync,
	input         VSync,

	output        VGA_CLK,
	output reg    VGA_CE,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,

	output        HDMI_CLK,
	output        HDMI_CE,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,
	output  [1:0] HDMI_SL,
	
	input   [2:0] fx,
	input         forced_scandoubler,
	inout  [21:0] gamma_bus
);

assign VGA_CLK = clk_video;
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = ~(HBlank | VBlank);

wire hs_fix,vs_fix;
sync_fix sync_v(VGA_CLK, HSync, hs_fix);
sync_fix sync_h(VGA_CLK, VSync, vs_fix);

reg hs,vs;
always @(posedge VGA_CLK) begin
	reg old_ce;
	old_ce <= ce_pix;
	VGA_CE <= 0;
	if(~old_ce & ce_pix) begin
		VGA_CE <= 1;
		hs <= hs_fix;
		if(~hs & hs_fix) vs <= vs_fix;
	end
end

generate
	if(DW == 6) begin
		assign VGA_R = {RGB_in[5:4],RGB_in[5:4],RGB_in[5:4],RGB_in[5:4]};
		assign VGA_G = {RGB_in[3:2],RGB_in[3:2],RGB_in[3:2],RGB_in[3:2]};
		assign VGA_B = {RGB_in[1:0],RGB_in[1:0],RGB_in[1:0],RGB_in[1:0]};
	end
	else if(DW == 8) begin
		assign VGA_R = {RGB_in[7:5],RGB_in[7:5],RGB_in[7:6]};
		assign VGA_G = {RGB_in[4:2],RGB_in[4:2],RGB_in[4:3]};
		assign VGA_B = {RGB_in[1:0],RGB_in[1:0],RGB_in[1:0],RGB_in[1:0]};
	end
	else if(DW == 9) begin
		assign VGA_R = {RGB_in[8:6],RGB_in[8:6],RGB_in[8:7]};
		assign VGA_G = {RGB_in[5:3],RGB_in[5:3],RGB_in[5:4]};
		assign VGA_B = {RGB_in[2:0],RGB_in[2:0],RGB_in[2:1]};
	end
	else begin
		assign VGA_R = {RGB_in[11:8],RGB_in[11:8]};
		assign VGA_G = {RGB_in[7:4],RGB_in[7:4]};
		assign VGA_B = {RGB_in[3:0],RGB_in[3:0]};
	end
endgenerate

assign HDMI_CLK = VGA_CLK;
assign HDMI_SL  = sl[1:0];
wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;
wire scandoubler = fx || forced_scandoubler;

video_mixer #(WIDTH+4, 1, GAMMA) video_mixer
(
	.clk_vid(HDMI_CLK),
	.ce_pix(VGA_CE),
	.ce_pix_out(HDMI_CE),

	.scandoubler(scandoubler),
	.hq2x(fx==1),
	.gamma_bus(gamma_bus),

	.R(VGA_R[7:4]),
	.G(VGA_G[7:4]),
	.B(VGA_B[7:4]),

	.HSync(hs),
	.VSync(vs),
	.HBlank(HBlank),
	.VBlank(VBlank),

	.VGA_R(HDMI_R),
	.VGA_G(HDMI_G),
	.VGA_B(HDMI_B),
	.VGA_VS(HDMI_VS),
	.VGA_HS(HDMI_HS),
	.VGA_DE(HDMI_DE)
);

endmodule
