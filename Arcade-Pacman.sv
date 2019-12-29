//============================================================================
//  Arcade: Pacman
//
//  Port to MiSTer
//  Copyright (C) 2017 Sorgelig
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

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;

`include "build_id.v" 
localparam CONF_STR = {
	"A.PACMAN;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"-,DIP Switches:;",
	"-;",
	"h1O8,Lives,3,5;",                        // club
	"h4O89,Lives,3,5,1,2;",                   // pacman/plus
	"h1OAB,Bonus,20000,40000,80000,None;",    // club
	"h4OAB,Bonus,10000,15000,20000,None;",    // pacman/plus
	"h2OGH,Lives,3,4,5,6;",                   // crush roller
	"h3OKL,Lives,1,2,3,4;",                   // birdiy
	"h2OI,First Pattern,Easy,Hard;",          // crush roller
	"h2OJ,Teleport Holes,On,Off;",            // crush roller
	"H3OC,Cabinet,Upright,Cocktail;",         // not birdiy
	"h4OD,Ghost names,Standard,Alternative;", // pacman/plus
	"OEF,Coins,1 Coin 2 Play, 2 Coins 1 Play, Free Play, 1 Coin 1 Play;", // all
	"-;",
	"R0,Reset;",
	"J1,Skip,Start 1P,Start 2P,Coin;",
	"jn,A,Start,Select,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vid;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),
	.outclk_1(clk_sys),
	.locked(pll_locked)
);

reg ce_6m;
always @(posedge clk_sys) begin
	reg [1:0] div;
	
	div <= div + 1'd1;
	ce_6m <= !div;
end

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joy1;
wire [15:0] joy2;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({mod_orig|mod_plus|mod_ms,mod_bird,mod_crush,mod_club,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1),
	.joystick_1(joy2),
	.ps2_key(ps2_key)
);

reg mod_plus = 0;
reg mod_club = 0;
reg mod_orig = 0;
reg mod_crush= 0;
reg mod_bird = 0;
reg mod_ms   = 0;
always @(posedge clk_sys) begin
	reg [7:0] mod = 0;
	if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout[7:0];
	
	mod_orig <= (mod == 0);
	mod_plus <= (mod == 1);
	mod_club <= (mod == 2);
	mod_crush<= (mod == 3);
	mod_bird <= (mod == 4);
	mod_ms   <= (mod == 5);
end

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire        <= pressed; // space
			'h014: btn_fire        <= pressed; // ctrl

			'h005: btn_start_1     <= pressed; // F1
			'h006: btn_start_2     <= pressed; // F2
			'h004: btn_coin        <= pressed; // F3
			
			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_fire_2      <= pressed; // A
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_coin  = 0;
reg btn_fire  = 0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;
reg btn_fire_2=0;

wire no_rotate = status[2] & ~direct_video;

wire m_up,m_down,m_left,m_right;
joyonedir jod
(
	clk_sys,
	mod_bird,
	{
		no_rotate ? btn_left  | joy1[1] : btn_up    | joy1[3],
		no_rotate ? btn_right | joy1[0] : btn_down  | joy1[2],
		no_rotate ? btn_down  | joy1[2] : btn_left  | joy1[1],
		no_rotate ? btn_up    | joy1[3] : btn_right | joy1[0]
	},
	{m_up,m_down,m_left,m_right}
);

wire m_up_2,m_down_2,m_left_2,m_right_2;
joyonedir jod_2
(
	clk_sys,
	mod_bird,
	{
		no_rotate ? btn_left_2  | joy2[1] : btn_up_2    | joy2[3],
		no_rotate ? btn_right_2 | joy2[0] : btn_down_2  | joy2[2],
		no_rotate ? btn_down_2  | joy2[2] : btn_left_2  | joy2[1],
		no_rotate ? btn_up_2    | joy2[3] : btn_right_2 | joy2[0]
	},
	{m_up_2,m_down_2,m_left_2,m_right_2}
);

wire m_fire     = btn_fire    | joy1[4];
wire m_fire_2   = btn_fire_2  | joy2[4];
wire m_start    = btn_start_1 | joy1[5] | joy2[5];
wire m_start_2  = btn_start_2 | joy1[6] | joy2[6];
wire m_coin     = btn_coin    | joy1[7] | joy2[7] | btn_coin_1 | btn_coin_2;

wire m_cheat    = (mod_orig | mod_plus) & (m_fire | m_fire_2);

wire hblank, vblank;
wire ce_vid = ce_6m;
wire hs, vs;
wire [2:0] r,g;
wire [1:0] b;

arcade_rotate_fx #(288,224,8) arcade_video
(
	.*,

	.clk_video(clk_vid),
	.ce_pix(ce_vid),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);

wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;

//pacman variants
wire [7:0]m_dip = {~status[13], 1'b1,status[11:10],~status[9]|mod_club,status[8],~status[15],status[14]};

//crush roller
wire [7:0]m_dip_cr = {1'b0,1'b0,status[19],~status[18],status[17:16],~status[15],status[14]};

//birdiy
wire [7:0]m_dip_b  = {1'b1,1'b1,1'b1,1'b0,status[21:20],~status[15],status[14]};

pacman pacman
(
	.O_VIDEO_R(r),
	.O_VIDEO_G(g),
	.O_VIDEO_B(b),
	.O_HSYNC(hs),
	.O_VSYNC(vs),
	.O_HBLANK(hblank),
	.O_VBLANK(vblank),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr && !ioctl_index),

	.O_AUDIO(audio),

	.in0_reg(~{1'b0,1'b0,  m_coin, m_cheat}),
	.in1_reg(~{status[12], m_start_2, m_start, 1'b0, m_down_2,m_right_2,m_left_2,m_up_2}),
	.dipsw_reg(mod_crush ? m_dip_cr : mod_bird ? m_dip_b : m_dip),

	.mod_plus(mod_plus),
	.mod_bird(mod_bird),
	.mod_ms(mod_ms),

	.in_a({m_down,m_right,m_left,m_up} | (mod_club ? 4'b0000 : {m_down_2,m_right_2,m_left_2,m_up_2})),
	.in_b(mod_club ? {m_down_2,m_right_2,m_left_2,m_up_2} : {m_down,m_right,m_left,m_up}),

	.RESET(RESET | status[0] |  buttons[1]|ioctl_download),
	.CLK(clk_sys),
	.ENA_6(ce_6m)
);

endmodule

module joyonedir
(
	input        clk,
	input        dis,
	input  [3:0] indir,
	output [3:0] outdir
);

reg  [3:0] mask = 0;
reg  [3:0] in1,in2;
wire [3:0] innew = in1 & ~in2;

assign outdir = in1 & mask;

always @(posedge clk) begin
	
	in1 <= indir;
	in2 <= in1;
	
	if(innew[0]) mask <= 1;
	if(innew[1]) mask <= 2;
	if(innew[2]) mask <= 4;
	if(innew[3]) mask <= 8;
	
	if(dis) mask <= '1;
end

endmodule
