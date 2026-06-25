--
-- A simulation model of Pacman hardware
-- Copyright (c) MikeJ - January 2006
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- You are responsible for any legal issues arising from your use of this code.
--
-- The latest version of this file can be found at: www.fpgaarcade.com
--
-- Email pacman@fpgaarcade.com
--
-- Revision list
--
-- version 006 Merge different variants by Alexey Melnikov
-- version 005 Papilio release by Jack Gassett
-- version 004 spartan3e release
-- version 003 Jan 2006 release, general tidy up
-- version 002 optional vga scan doubler
-- version 001 initial release
--
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_unsigned.all;
  use ieee.numeric_std.all;

library UNISIM;

entity PACMAN is
port
(
	O_VIDEO_R  : out std_logic_vector(2 downto 0);
	O_VIDEO_G  : out std_logic_vector(2 downto 0);
	O_VIDEO_B  : out std_logic_vector(1 downto 0);
	O_HSYNC    : out std_logic;
	O_VSYNC    : out std_logic;
	O_HBLANK   : out std_logic;
	O_VBLANK   : out std_logic;
	--
	O_AUDIO    : out std_logic_vector(9 downto 0);
	--
	in0        : in  std_logic_vector(7 downto 0);
	in1        : in  std_logic_vector(7 downto 0);
	dipsw1     : in  std_logic_vector(7 downto 0);
	dipsw2     : in  std_logic_vector(7 downto 0);
	--
	mod_plus   : in  std_logic;
	mod_jmpst  : in  std_logic;
	mod_bird   : in  std_logic;
	mod_mrtnt  : in  std_logic;
	mod_ms     : in  std_logic;
	mod_woodp  : in  std_logic;
	mod_eeek   : in  std_logic;
	mod_glob   : in  std_logic;
	mod_alib   : in  std_logic;
	mod_ponp   : in  std_logic;
	mod_van    : in  std_logic;
	mod_dshop  : in  std_logic;
	mod_club   : in  std_logic;

	flip_screen : in  std_logic;
	h_offset    : in  std_logic_vector(2 downto 0);
	v_offset    : in  std_logic_vector(2 downto 0);

	--
	mod_jr     : in  std_logic := '0';      -- Jr. Pac-Man

	dn_addr    : in  std_logic_vector(15 downto 0);
	dn_data    : in  std_logic_vector(7 downto 0);
	dn_wr      : in  std_logic;

	pause      : in  std_logic;

	-- high score
	hs_address      : in  std_logic_vector(11 downto 0);
	hs_data_in      : in  std_logic_vector(7 downto 0);
	hs_data_out     : out std_logic_vector(7 downto 0);
	hs_write_enable : in  std_logic;
	hs_access_read  : in  std_logic;
	hs_access_write : in  std_logic;

	--
	RESET      : in  std_logic;
	CLK        : in  std_logic;
	ENA_6      : in  std_logic;
	ENA_4      : in  std_logic;
	ENA_1M79   : in  std_logic
);
end;

architecture RTL of PACMAN is
	-- timing
	signal hcnt             : std_logic_vector(8 downto 0) := "010000000"; -- 80
	signal vcnt             : std_logic_vector(8 downto 0) := "011111000"; -- 0F8
	signal vcnt_offset      : std_logic_vector(8 downto 0);

	signal do_vcnt_check    : boolean;
	signal hsync            : std_logic;
	signal vsync            : std_logic;
	signal hblank           : std_logic;
	signal vblank           : std_logic := '1';

	-- cpu
	signal cpu_m1_l         : std_logic;
	signal cpu_mreq_l       : std_logic;
	signal cpu_iorq_l       : std_logic;
	signal cpu_rd_l         : std_logic;
	signal cpu_wr_l         : std_logic;
	signal cpu_rfsh_l       : std_logic;
	signal cpu_int_l        : std_logic;
	signal cpu_addr         : std_logic_vector(15 downto 0);
	signal cpu_data_out     : std_logic_vector(7 downto 0);
	signal cpu_data_in      : std_logic_vector(7 downto 0);

	signal vram_l           : std_logic;
	signal ram_data         : std_logic_vector(7 downto 0);
	signal ram2_we          : std_logic;
	signal ram2_cs          : std_logic;
	signal ram2_data        : std_logic_vector(7 downto 0);

	signal mcnt             : std_logic_vector(7 downto 0);
	signal mcnt2            : std_logic_vector(10 downto 0);
	signal dcnt             : std_logic_vector(1 downto 0);
	signal old_rd_l         : std_logic;
	signal old_rd_l2        : std_logic;
	signal rom_data         : std_logic_vector(7 downto 0);

	signal sync_bus_cs_l    : std_logic;

	signal control_reg      : std_logic_vector(7 downto 0);
	signal c_flip           : std_logic;
	signal c_int            : std_logic;
	signal c_sound          : std_logic;

	signal hp               : std_logic_vector( 4 downto 0);
	signal vp               : std_logic_vector( 4 downto 0);
	signal vram_addr        : std_logic_vector(11 downto 0);
	signal vram_addr_ab     : std_logic_vector(11 downto 0);
	signal ab               : std_logic_vector(11 downto 0);

	signal sync_bus_db      : std_logic_vector(7 downto 0);
	signal sync_bus_r_w_l   : std_logic;
	signal sync_bus_wreq_l  : std_logic;
	signal sync_bus_stb     : std_logic;

	signal inj              : std_logic_vector(3 downto 0);

	signal cpu_vec_reg      : std_logic_vector(7 downto 0);
	signal sync_bus_reg     : std_logic_vector(7 downto 0);

	-- more decode
	signal wr0_l            : std_logic;
	signal wr1_l            : std_logic;
	signal wr2_l            : std_logic;
	signal iodec_out_l      : std_logic;
	signal iodec_wdr_l      : std_logic;
	signal iodec_in0_l      : std_logic;
	signal iodec_in1_l      : std_logic;
	signal iodec_dipsw1_l   : std_logic;
	signal iodec_dipsw2_l   : std_logic;
	signal iodec_myst1_l    : std_logic;
	signal iodec_myst2_l    : std_logic;
	signal iodec_nop_l      : std_logic;
	signal iodec_01         : std_logic;

	-- watchdog
	signal watchdog_cnt     : std_logic_vector(7 downto 0);
	signal watchdog_reset_l : std_logic;

	signal sn1_ce           : std_logic;
	signal sn2_ce           : std_logic;
	signal sn1_ready        : std_logic;
	signal sn2_ready        : std_logic;
	signal sn_d             : std_logic_vector(7 downto 0);
	signal old_we           : std_logic;
	signal wav1s,wav2s      : signed(7 downto 0);
	signal wav1u,wav2u,wav3u: std_logic_vector(7 downto 0);
	signal wav4u            : std_logic_vector(7 downto 0);
	signal ay_we            : std_logic;
	-- Jr. Pac-Man program ROM (mod_jr)
	signal jr_rom_data      : std_logic_vector(7 downto 0);
	signal jr_rom_sel       : std_logic;
	signal jr_prog_dl       : std_logic;
	signal jr_dn_waddr      : std_logic_vector(15 downto 0);
	-- Jr. Pac-Man latch2 (5070) + scroll (5080)
	signal jr_latch2        : std_logic_vector(7 downto 0);
	signal jr_scroll        : std_logic_vector(7 downto 0);
	signal jr_latch2_l      : std_logic;
	signal jr_scroll_l      : std_logic;
	signal jr_palbank       : std_logic;
	signal jr_colortabbank  : std_logic;
	signal jr_bgpriority    : std_logic;
	signal jr_charbank      : std_logic;
	signal jr_spritebank    : std_logic;
	-- Jr. Pac-Man video RAM address
	signal jr_mc            : std_logic_vector(5 downto 0);
	signal jr_mr            : std_logic_vector(5 downto 0);
	signal jr_vy            : std_logic_vector(8 downto 0);
	signal jr_hud           : std_logic;
	signal jr_pf_scan       : std_logic_vector(11 downto 0);
	signal jr_hud_scan      : std_logic_vector(11 downto 0);
	signal jr_code_addr     : std_logic_vector(11 downto 0);
	signal jr_color_addr    : std_logic_vector(11 downto 0);
	signal jr_vram_addr     : std_logic_vector(11 downto 0);

	-- Jr. Pac-Man program-ROM DECRYPTION (jrpacman.cpp init_jrpacman, lines 384-425).
	-- The aux-board encryption PALs garble bits 0, 2, 7. MAME decrypts by walking the
	-- maincpu region linearly and XORing each byte with a run-length-encoded value.
	-- The table below is that exact table; A index = linear maincpu addr = CPU addr.
	-- OUR download skips the 4000-7FFF gap (dn 4000-9FFF -> CPU 8000-DFFF). That gap is
	-- entirely inside entry #8's {0x9968,0x00} no-XOR run, so entry #8 is shortened by
	-- 0x4000 -> {0x5968,0x00} to keep the later XORs aligned to the download offset.
	-- Walked once per download byte; gated on mod_jr + jr_prog_dl (Pac-Man untouched).
	-- ROBUST-TABLE-2026-06-25: was a record-array constant (jr_xor_tbl_t) indexed by a signal.
	-- That pattern mis-synthesized on Quartus 17.0 (the .val lookup read as 0x00 in silicon =>
	-- encrypted zones left RAW => boot reached the grid but crashed on the first encrypted code
	-- at $9C00). Split into two flat constant arrays (reliable ROM inference). Values IDENTICAL
	-- to the old table; entry #8 still 0x5968 (gap-removed). See JRPACMAN_PORT_NOTES.md.
	type jr_cnt_t is array(0 to 79) of unsigned(15 downto 0);
	type jr_val_t is array(0 to 79) of std_logic_vector(7 downto 0);
	constant JR_CNT_TBL : jr_cnt_t := (
		x"00C1",x"0002",x"0004",x"0006",x"0003",x"0002",
		x"0009",x"0004",x"5968",x"0001",x"0002",x"0001",
		x"0009",x"0002",x"0009",x"0001",x"00AF",x"000E",
		x"0002",x"0004",x"001E",x"0001",x"0002",x"0001",
		x"0002",x"0002",x"0009",x"0002",x"0009",x"0002",
		x"0083",x"0001",x"0001",x"0001",x"0002",x"0001",
		x"0003",x"0003",x"0002",x"0001",x"0003",x"0003",
		x"0003",x"0001",x"002E",x"0078",x"0001",x"0001",
		x"0001",x"0001",x"0001",x"0002",x"0001",x"0001",
		x"0002",x"0001",x"0001",x"0002",x"0001",x"0001",
		x"0001",x"0001",x"0001",x"0001",x"0002",x"0001",
		x"0001",x"0002",x"0001",x"0001",x"0001",x"0001",
		x"01B0",x"0001",x"0002",x"00AD",x"0031",x"005C",
		x"0005",x"604E"
	);
	constant JR_VAL_TBL : jr_val_t := (
		x"00",x"80",x"00",x"80",x"00",x"80",x"00",x"80",
		x"00",x"80",x"00",x"80",x"00",x"80",x"00",x"80",
		x"00",x"04",x"00",x"04",x"00",x"80",x"00",x"80",
		x"00",x"80",x"00",x"80",x"00",x"80",x"00",x"04",
		x"01",x"00",x"05",x"00",x"04",x"01",x"00",x"04",
		x"01",x"00",x"04",x"01",x"00",x"01",x"04",x"05",
		x"00",x"01",x"04",x"00",x"01",x"04",x"00",x"01",
		x"04",x"00",x"01",x"04",x"05",x"00",x"01",x"04",
		x"00",x"01",x"04",x"00",x"01",x"04",x"05",x"00",
		x"01",x"00",x"01",x"00",x"01",x"00",x"01",x"00"
	);
	-- Jr program-ROM DECRYPT, address-indexed (rom_descrambler-style: store raw, decode statelessly). Replaces the
	-- old stateful run-length walker, which mis-counted the 0x5968 run in silicon and garbled the post-grid code
	-- (HW-confirmed root cause + fix 2026-06-25). JR_BOUND(i) = prefix sum of JR_CNT_TBL = download offset where
	-- entry i begins (compile-time constant).
	type jr_bound_t is array(0 to 80) of unsigned(15 downto 0);
	function jr_calc_bounds return jr_bound_t is
		variable b   : jr_bound_t;
		variable acc : unsigned(15 downto 0) := (others => '0');
	begin
		for i in 0 to 79 loop
			b(i) := acc;
			acc  := acc + JR_CNT_TBL(i);
		end loop;
		b(80) := acc;
		return b;
	end function;
	constant JR_BOUND  : jr_bound_t := jr_calc_bounds;
	signal jr_xor_comb : std_logic_vector(7 downto 0);
	signal jr_dn_data       : std_logic_vector(7 downto 0);          -- decrypted download byte

	component ym2149 is port
	(
		CLK        : in std_logic;
		CE         : in std_logic;
		RESET      : in std_logic;
		BDIR       : in std_logic;
		BC         : in std_logic;
		DI         : in std_logic_vector(7 downto 0);
		DO         : out std_logic_vector(7 downto 0);
		CHANNEL_A  : out std_logic_vector(7 downto 0);
		CHANNEL_B  : out std_logic_vector(7 downto 0);
		CHANNEL_C  : out std_logic_vector(7 downto 0);

		SEL        : in std_logic;
		MODE       : in std_logic;
		IOA_in     : in std_logic_vector(7 downto 0);
		IOA_out    : out std_logic_vector(7 downto 0);

		IOB_in     : in std_logic_vector(7 downto 0);
		IOB_out    : out std_logic_vector(7 downto 0)
	);
	end component;
begin

--
-- video timing
--
p_hvcnt : process
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		if hcnt = "111111111" then
			hcnt <= "010000000"; -- 080
		else
			hcnt <= hcnt +"1";
		end if;
		-- hcnt 8 on circuit is 256H_L
		if do_vcnt_check then
			if vcnt = "111111111" then
				vcnt <= "011111000"; -- 0F8
			else
				vcnt <= vcnt +"1";
			end if;
		end if;
	end if;
end process;

vcnt_offset <= vcnt + v_offset;
vsync <= not vcnt_offset(8);
do_vcnt_check <= (hcnt = "010101111"); -- 0AF

p_sync : process
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		-- Timing hardware is coded differently to the real hw
		-- to avoid the use of multiple clocks. Result is identical.

		if (hcnt = "010010111") then -- 097
			O_HBLANK <= '1';
		elsif (hcnt = "010001111" and mod_ponp = '0') or (hcnt = "111111111" and mod_ponp = '1') then -- 08F
			hblank <= '1';
		elsif (hcnt = "011101111" and mod_ponp = '0') or (hcnt = "011111111" and mod_ponp = '1') then
			hblank <= '0'; -- 0EF
		elsif (hcnt = "011110111") then -- 0F7
			O_HBLANK <= '0';
		end if;

		if (hcnt = "010101111" + h_offset) then -- 0AF (+h_offset)
			hsync <= '1';
		elsif (hcnt = "011001111" + h_offset) then -- 0CF (+h_offset)
			hsync <= '0';
		end if;

		if do_vcnt_check then
			if (vcnt = "111101111") then -- 1EF
				vblank <= '1';
			elsif (vcnt = "100001111") then -- 10F
				vblank <= '0';
			end if;
		end if;
	end if;
end process;

--
-- cpu
--
p_irq_req_watchdog : process
	variable rising_vblank : boolean;
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		rising_vblank := (hcnt = "010101111") and (vcnt = "111101111"); -- AF and 1EF
		-- interrupt 8c

		if (c_int = '0') then
			cpu_int_l <= '1';
		elsif rising_vblank then -- 1EF
			cpu_int_l <= '0';
		end if;

		-- watchdog 8c
		-- note sync reset
		if (reset = '1') then
			watchdog_cnt <= X"FF";
		elsif (iodec_wdr_l = '0') then
			watchdog_cnt <= X"00";
		elsif (pause = '1') then
			watchdog_cnt <= X"00";
		elsif rising_vblank then
			watchdog_cnt <= watchdog_cnt + "1";
		end if;

		watchdog_reset_l <= '1';
		if (watchdog_cnt = X"FF") then
			watchdog_reset_l <= '0';
		end if;
	end if;
end process;

u_cpu : work.T80sed
port map (
	RESET_n => watchdog_reset_l and (not reset),
	CLK_n   => clk,
	CLKEN   => hcnt(0) and ena_6,
	WAIT_n  => sync_bus_wreq_l and (not pause),
	INT_n   => cpu_int_l or     mod_van,
	NMI_n   => cpu_int_l or not mod_van,
	BUSRQ_n => '1',
	M1_n    => cpu_m1_l,
	MREQ_n  => cpu_mreq_l,
	IORQ_n  => cpu_iorq_l,
	RD_n    => cpu_rd_l,
	WR_n    => cpu_wr_l,
	RFSH_n  => cpu_rfsh_l,
	HALT_n  => open,
	BUSAK_n => open,
	A       => cpu_addr,
	DI      => cpu_data_in,
	DO      => cpu_data_out
);

--
-- primary addr decode
--
-- syncbus 0x4000 - 0x7FFF
-- Pac-Man uses cpu_addr(14)=1 as shorthand for the VRAM/IO sync-bus region (4000-7FFF),
-- valid only because Pac-Man ROM never has A14=1. Jr's program ROM extends to C000-DFFF
-- (A14=1), so for Jr the sync bus must be restricted to 4000-7FFF (A15:14="01"); otherwise
-- C000-DFFF fetches return sync_bus_reg (VRAM) instead of jr_rom_data + inject WAITs.
sync_bus_cs_l   <= '0' when cpu_mreq_l = '0' and cpu_rfsh_l = '1' and
                       ( (mod_jr = '0' and cpu_addr(14) = '1') or
                         (mod_jr = '1' and cpu_addr(15 downto 14) = "01") ) else '1';
sync_bus_wreq_l <= '0' when sync_bus_cs_l = '0' and hcnt(1) = '1' and cpu_rd_l = '0' else '1';
sync_bus_stb    <= '0' when sync_bus_cs_l = '0' and hcnt(1) = '0' else '1';
sync_bus_r_w_l  <= '0' when sync_bus_stb  = '0' and cpu_rd_l = '1' else '1';
 
--
-- sync bus custom ic
--
p_sync_bus_reg : process
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		-- register on sync bus module that is used to store interrupt vector
		if (cpu_iorq_l = '0') and (cpu_m1_l = '1') then
			cpu_vec_reg <= cpu_data_out;
		end if;

		-- read holding reg
		if (hcnt(1 downto 0) = "01") then
			sync_bus_reg <= cpu_data_in;
		end if;
	end if;
end process;

--
-- vram addr custom ic
--
u_vram_addr : work.PACMAN_VRAM_ADDR
port map (
	AB      => vram_addr_ab,
	H256_L  => hcnt(8),
	H128    => hcnt(7),
	H64     => hcnt(6),
	H32     => hcnt(5),
	H16     => hcnt(4),
	H8      => hcnt(3),
	H4      => hcnt(2),
	H2      => hcnt(1),
	H1      => hcnt(0),
	V128    => vcnt(7),
	V64     => vcnt(6),
	V32     => vcnt(5),
	V16     => vcnt(4),
	V8      => vcnt(3),
	V4      => vcnt(2),
	V2      => vcnt(1),
	V1      => vcnt(0),
	FLIP    => c_flip
);

hp <= hcnt(7 downto 3) when c_flip = '0' else not hcnt(7 downto 3);
vp <= vcnt(7 downto 3) when c_flip = '0' else not vcnt(7 downto 3);
-- Jr. Pac-Man video RAM address (mod_jr) — faithful jrpacman_scan_rows (pacman_v.cpp:607; 36x54 map,
-- per-column scroll) + per-column colour.
-- FIXED 2026-06-25 (origin bug): hcnt resets to 0x080, so hcnt(8:3) is 16-based and the visible line WRAPS
-- across the 256H bit (hcnt(8)); vcnt likewise. MAME's col-=2 / row+=2 therefore land on the 256H/256V
-- boundary (0x20), NOT 0x02. The old -0x02 put the HUD/playfield split on the wrong columns -> the scrolling
-- maze was rendered into the non-scrolling band (edge strips -> corners after 90deg rot) while the HUD region
-- (videoram 0x700+) filled the middle as garbage. Subtracting 0x20 realigns: playfield = cols 2..33,
-- HUD = cols 0,1,34,35; HUD off-screen test (mr&0x20) now stays 0 over the visible rows instead of always 1.
--   mc = map col = (hcnt 8:3) - 0x20   (== MAME col-2, wrap-correct); HUD edges when mc & 0x20.
--   mr = map row = ((vcnt[+scroll]) 8:3) - 0x20  (== MAME row+2; scroll applied to PLAYFIELD only).
--   code: playfield -> mc + mr*32 ; HUD -> mr + (((mc&3)|0x38)<<5) ; off-screen (HUD & mr&0x20) -> 0x77F.
--   colour: playfield -> videoram[mc & 0x1f] ; HUD -> code_addr + 0x80.   phase: hcnt(2)=0 code, =1 colour.
--   STILL TODO (separate from this fix): c_flip not applied to mc/mr (cf. hp/vp line 482-483); far-scroll mr
--   has no mod-54 wrap. Neither affects the un-flipped, near-zero-scroll boot/attract screen.
jr_mc <= hcnt(8 downto 3) - "100000";                                       -- was -"000010" (0x02); 0x20 = 256H origin
jr_hud <= jr_mc(5);
jr_vy <= vcnt + ('0' & jr_scroll);                                          -- scrolled pixel-Y (scroll is in PIXELS)
jr_mr <= (jr_vy(8 downto 3) - "100000") when jr_hud = '0'                    -- was jr_vy(8:3) / vcnt(8:3) (no -0x20)
    else (vcnt(8 downto 3)  - "100000");                                    -- tile row - 0x20 (256V origin); playfield scrolled
jr_pf_scan  <= ("000000" & jr_mc) + ('0' & jr_mr & "00000");
jr_hud_scan <= ("000000" & jr_mr) + ('0' & "1110" & jr_mc(1 downto 0) & "00000");
jr_code_addr  <= x"77F"      when (jr_hud = '1' and jr_mr(5) = '1')   -- off-screen
            else jr_hud_scan when  jr_hud = '1'                       -- HUD top/bottom rows
            else jr_pf_scan;                                          -- playfield
jr_color_addr <= ("0000000" & jr_mc(4 downto 0)) when jr_hud = '0'    -- playfield: col & 0x1f
            else (jr_code_addr + x"080");                             -- HUD: scan + 0x80
jr_vram_addr  <= jr_code_addr when hcnt(2) = '0' else jr_color_addr;
vram_addr <= jr_vram_addr when mod_jr = '1' and hblank = '0' else  -- Jr tile scan on visible line; hblank falls through to vram_addr_ab for sprite-RAM fetch (0x3F0-0x3FF)
             vram_addr_ab when mod_alib = '0' and mod_ponp = '0' else '0' & hcnt(2) & vp & hp when hcnt(8)='1' else
             x"FF" & hcnt(6 downto 4) & hcnt(2) when hblank = '1' and mod_ponp = '1' else
             x"EF" & hcnt(6 downto 4) & hcnt(2) when hblank = '1' else
             '0' & hcnt(2) & hp(3) & hp(3) & hp(3) & hp(3) & hp(0) & vp;

--When 2H is low, the CPU controls the bus.
ab <= cpu_addr(11 downto 0) when hcnt(1) = '0' else vram_addr;
sync_bus_db <= cpu_data_out when hcnt(1) = '0' else ram_data;

--vram_l <= not (not (cpu_addr(12) or sync_bus_stb) or (hcnt(1) and hcnt(0)));
vram_l <= (cpu_addr(12) or sync_bus_stb) and not (hcnt(1) and hcnt(0));

iodec_01 <= '1' when cpu_addr(5 downto 1) = "00000" else '0';

p_io_decode_comb : process(sync_bus_r_w_l, sync_bus_stb, ab, cpu_addr, mod_bird, mod_alib, iodec_01, mod_dshop)
	variable sel  : std_logic_vector(2 downto 0);
	variable dec  : std_logic_vector(7 downto 0);
	variable selb : std_logic_vector(1 downto 0);
	variable decb : std_logic_vector(3 downto 0);
begin
	-- WRITE

	-- out_l 0x5000 - 0x503F control space

	-- wr0_l 0x5040 - 0x504F sound
	-- wr1_l 0x5050 - 0x505F sound
	-- wr2_l 0x5060 - 0x506F sprite

	--       0x5080 - 0x50BF unused

	-- wdr_l 0x50C0 - 0x50FF watchdog reset

	-- READ

	-- in0_l   0x5000 - 0x503F in port 0
	-- in1_l   0x5040 - 0x507F in port 1
	-- dipsw_l 0x5080 - 0x50BF dip switches

	-- 7J
	dec := "11111111";
	sel := sync_bus_r_w_l & ab(7) & ab(6);
	if (cpu_addr(12) = '1') and ( sync_bus_stb = '0')  then
		case sel is
			when "000" => dec := "11111110";
			when "001" => dec := "11111101";
			when "010" => dec := "11111011";
			when "011" => dec := "11110111";
			when "100" => dec := "11101111";
			when "101" => dec := "11011111";
			when "110" => dec := "10111111";
			when "111" => dec := "01111111";
			when others => null;
		end case;
	end if;

	if mod_alib = '1' then
		iodec_wdr_l   <= dec(0);
		iodec_out_l   <= dec(3);
	else
		iodec_out_l   <= dec(0);
		iodec_wdr_l   <= dec(3);
	end if;

	iodec_in0_l   <= dec(4);
	iodec_in1_l   <= dec(5);
	iodec_dipsw1_l<= dec(6);
	iodec_dipsw2_l<= dec(7) or mod_alib;

	iodec_myst1_l <= dec(7) or not iodec_01 or     cpu_addr(0) or not mod_alib;
	iodec_myst2_l <= dec(7) or not iodec_01 or not cpu_addr(0) or not mod_alib;
	iodec_nop_l   <= dec(7) or     iodec_01                    or not mod_alib;

	-- 7M
	decb := "1111";
	selb := ab(5) & ab(4);
	if (dec(2) = '0' and mod_bird = '1') or (dec(1) = '0' and mod_bird = '0') then
		case selb is
			when "00" => decb := "1110";
			when "01" => decb := "1101";
			when "10" => decb := "1011";
			when "11" => decb := "0111";
			when others => null;
		end case;
	end if;

	wr0_l <= decb(0);
	wr1_l <= decb(1);
	wr2_l <= decb(2);

	if mod_alib = '1' then
		wr2_l <= decb(1);
		wr1_l <= decb(2);
	end if;

	if mod_dshop = '1' then
		wr2_l <= dec(1);
	end if;
end process;

p_control_reg : process
begin
	-- 8 bit addressable latch 7K
	-- (made into register)

	-- 0 interrupt ena
	-- 1 sound ena
	-- 2 not used
	-- 3 flip
	-- 4 1 player start lamp
	-- 5 2 player start lamp
	-- 6 coin lockout
	-- 7 coin counter

	wait until rising_edge(clk);
	if (ena_6 = '1') then
		if (watchdog_reset_l = '0') then
			control_reg <= (others => '0');
		elsif (iodec_out_l = '0') then
			control_reg(to_integer(unsigned(cpu_addr(2 downto 0)))) <= cpu_data_out(0);
		end if;
	end if;
end process;

c_flip <= flip_screen xor control_reg(1) when mod_alib = '1' else flip_screen xor control_reg(5) when mod_bird = '1' else control_reg(3) xor flip_screen;
c_sound<= control_reg(0) when mod_alib = '1' else control_reg(3) when mod_bird = '1' else control_reg(1);
c_int  <= control_reg(2) when mod_alib = '1' else control_reg(1) when mod_bird = '1' else control_reg(0);

p_mcnt : process
begin
	wait until rising_edge(clk);
	mcnt <= (mcnt + "1") + ("0000000" & (in0(3) xor in0(2) xor in0(1) xor in0(0)));
	if (ena_6 = '1') then
		old_rd_l2 <= cpu_rd_l;
		if iodec_myst2_l = '0' and old_rd_l2 = '1' and cpu_rd_l = '0' then
			mcnt2 <= mcnt2 + "1";
		end if;
	end if;
end process;
 

inj <= in0(3 downto 0) when control_reg(5 downto 4) = "01" or mod_club = '0' else
       in1(3 downto 0) when control_reg(5 downto 4) = "10" else
       in0(3 downto 0) and in1(3 downto 0);

cpu_data_in <=	cpu_vec_reg               when cpu_iorq_l = '0' and cpu_m1_l = '0' else 
               sync_bus_reg              when sync_bus_wreq_l = '0' else
               ram2_data                 when ram2_cs = '1'         else
               jr_rom_data               when mod_jr = '1' and jr_rom_sel = '1' else -- Jr ROM: 0000-3FFF + 8000-DFFF
               rom_data                  when mod_jr = '0' and cpu_addr(14) = '0'  else -- ROM at 0000 - 3fff / 8000 - bfff
               in0(7 downto 4) & inj     when iodec_in0_l = '0'     else
               in1                       when iodec_in1_l = '0'     else
               dipsw1                    when iodec_dipsw1_l = '0'  else
               dipsw2                    when iodec_dipsw2_l = '0'  else
               "0000" & mcnt(3 downto 0) when iodec_myst1_l = '0'   else
               "0000000" & mcnt2(10)     when iodec_myst2_l = '0'   else
               x"BF"                     when iodec_nop_l   = '0'   else
               ram_data;

-- Jr. Pac-Man program ROM (40KB), gated on mod_jr. CPU sees ROM at 0000-3FFF and 8000-DFFF.
jr_rom_sel  <= '1' when (cpu_addr(15 downto 14) = "00") or
                        (cpu_addr(15) = '1' and cpu_addr(15 downto 13) /= "111") else '0';
jr_prog_dl  <= '1' when dn_addr < x"A000" else '0';   -- program region of the Jr download blob (8d,8e,8h,8j,8k @ dn 0000-9FFF)
-- Store the contiguous blob at the CPU addresses: dn 0000-3FFF stays; dn 4000-9FFF -> 8000-DFFF.
jr_dn_waddr <= dn_addr when dn_addr < x"4000" else (dn_addr + x"4000");

-- ADDRESS-INDEXED decrypt (rom_descrambler-style: stateless, no run counter to drift across the 0x5968 run).
-- Combinational XOR value = entry whose [JR_BOUND(i),JR_BOUND(i+1)) range contains dn_addr.
p_jr_decode_comb : process(dn_addr)
	variable v : std_logic_vector(7 downto 0);
begin
	v := JR_VAL_TBL(0);
	for i in 0 to 79 loop
		if unsigned(dn_addr) >= JR_BOUND(i) then
			v := JR_VAL_TBL(i);
		end if;
	end loop;
	jr_xor_comb <= v;
end process;
jr_dn_data <= dn_data xor jr_xor_comb;   -- decrypted program byte (mask 0x00 outside the encrypted zones)

u_jr_prog_rom : work.dpram generic map (16,8)
port map
(
	clock_a   => clk,
	address_a => cpu_addr,
	data_a    => x"00",
	q_a       => jr_rom_data,
	clock_b   => clk,
	wren_b    => dn_wr and mod_jr and jr_prog_dl,
	address_b => jr_dn_waddr,
	data_b    => jr_dn_data
);

-- Jr. Pac-Man latch2 (0x5070-0x5077, LS259 1H) and scroll (0x5080), gated on mod_jr.
jr_latch2_l <= '0' when mod_jr='1' and sync_bus_stb='0' and sync_bus_r_w_l='0' and cpu_addr(12)='1' and ab(7 downto 3)="01110" else '1';
jr_scroll_l <= '0' when mod_jr='1' and sync_bus_stb='0' and sync_bus_r_w_l='0' and cpu_addr(12)='1' and ab(7 downto 0)=x"80" else '1';

p_jr_latch2 : process begin
	wait until rising_edge(clk);
	if ena_6 = '1' then
		if watchdog_reset_l = '0' then
			jr_latch2 <= (others => '0');
		elsif jr_latch2_l = '0' then
			jr_latch2(to_integer(unsigned(cpu_addr(2 downto 0)))) <= cpu_data_out(0);
		end if;
	end if;
end process;

p_jr_scroll : process begin
	wait until rising_edge(clk);
	if ena_6 = '1' then
		if watchdog_reset_l = '0' then
			jr_scroll <= (others => '0');
		elsif jr_scroll_l = '0' then
			jr_scroll <= cpu_data_out;
		end if;
	end if;
end process;

jr_palbank      <= jr_latch2(0);
jr_colortabbank <= jr_latch2(1);
jr_bgpriority   <= jr_latch2(3);
jr_charbank     <= jr_latch2(4);
jr_spritebank   <= jr_latch2(5);

u_rams : work.dpram generic map (12,8)
port map
(
	clock_a   => clk,
--	enable_a  => ena_6,
	wren_a    => not sync_bus_r_w_l and not vram_l and ena_6 and not (hs_access_read or hs_access_write),
	address_a => ab(11 downto 0),
	data_a    => cpu_data_out, -- cpu only source of ram data
	q_a       => ram_data,
	clock_b   => clk,
	address_b => hs_address,
   enable_b  => hs_access_read or hs_access_write,
	wren_b    => hs_write_enable,
	data_b    => hs_data_in,
	q_b       => hs_data_out


);

ram2_we <= '1' when cpu_wr_l = '0' and cpu_mreq_l = '0' and cpu_rfsh_l = '1' else '0';
ram2_cs <= '1' when cpu_addr(15 downto 12) = X"9" and mod_alib = '1' else '0';

u_ram2 : work.dpram generic map (10,8)
port map
(
	clock_a   => clk,
	enable_a  => ena_6,
	wren_a    => ram2_we and ram2_cs,
	address_a => cpu_addr(9 downto 0),
	data_a    => cpu_data_out,
	q_a       => ram2_data,
	clock_b   => clk,
	address_b => cpu_addr(9 downto 0)
);

eeek_decrypt : process
begin
	wait until rising_edge(clk);
	if watchdog_reset_l = '0' then
		if mod_eeek = '1' then
			dcnt <= "01";
		else
			dcnt <= "10";
		end if;
	else
		old_rd_l <= cpu_rd_l;
		if old_rd_l = '1' and cpu_rd_l = '0' and cpu_iorq_l = '0' and cpu_m1_l = '1' then
			if cpu_addr(0) = '1' then
				dcnt <= dcnt - "1";
			else
				dcnt <= dcnt + "1";
			end if;
		end if;
	end if;
end process;

u_program_rom: work.rom_descrambler
port map(
	CLK      => clk,
	MRTNT    => mod_mrtnt,
	MSPACMAN => mod_ms,
	EEEK     => mod_eeek,
	GLOB     => mod_glob,
	PLUS     => mod_plus,
	JMPST		=> mod_jmpst,
	dcnt     => dcnt,
	cpu_m1_l => cpu_m1_l, 
	addr     => cpu_addr,
	data     => rom_data,
	dn_addr  => dn_addr,
	dn_data  => dn_data,
	dn_wr    => dn_wr
);

--
-- video subsystem
--
u_video : work.PACMAN_VIDEO
port map (
	I_HCNT    => hcnt,
	I_VCNT    => vcnt,
	--
	I_AB      => ab,
	I_DB      => sync_bus_db,
	--
	I_HBLANK  => hblank,
	I_VBLANK  => vblank,
	I_FLIP    => c_flip,
	I_WR2_L   => wr2_l,
	--
	dn_addr   => dn_addr,
	dn_data   => dn_data,
	dn_wr     => dn_wr,
	--
	O_RED     => O_VIDEO_R,
	O_GREEN   => O_VIDEO_G,
	O_BLUE    => O_VIDEO_B,
	--
	MRTNT     => mod_mrtnt or mod_woodp,
	PONP      => mod_ponp and not mod_van,
	ENA_6     => ena_6,
	CLK       => clk,
	flip_screen => flip_screen,

	mod_jr          => mod_jr,
	jr_scroll       => jr_scroll,
	jr_charbank     => jr_charbank,
	jr_spritebank   => jr_spritebank,
	jr_palbank      => jr_palbank,
	jr_colortabbank => jr_colortabbank,
	jr_bgpriority   => jr_bgpriority,
	jr_hud          => jr_hud
);

O_HSYNC   <= hSync;
O_VSYNC   <= vSync;
O_VBLANK  <= vblank;

--
--
-- audio subsystem
--
u_audio : work.PACMAN_AUDIO
port map (
	I_HCNT        => hcnt,
	--
	I_AB          => ab,
	I_DB          => sync_bus_db,
	--
	I_WR1_L       => wr1_l,
	I_WR0_L       => wr0_l,
	I_SOUND_ON    => c_sound,
	mod_jr        => mod_jr,
	--
	dn_addr       => dn_addr,
	dn_data       => dn_data,
	dn_wr         => dn_wr,
	--
	O_AUDIO       => wav4u,
	ENA_6         => ena_6 and (not pause),
	CLK           => clk
);

------------------------------------------

process(clk, reset) begin
	if reset = '1' then
		sn1_ce <= '1';
		sn2_ce <= '1';
	elsif rising_edge(clk) then

		if sn1_ready = '1' then
			sn1_ce <= '1';
		end if;

		if sn2_ready = '1' then
			sn2_ce <= '1';
		end if;

		old_we <= cpu_wr_l;
		if old_we = '1' and cpu_wr_l = '0' and cpu_iorq_l = '0' then
			if cpu_addr(7 downto 0) = X"01" then
				sn1_ce <= '0';
				sn_d <= cpu_data_out;
			end if;
			if cpu_addr(7 downto 0) = X"02" then
				sn2_ce <= '0';
				sn_d <= cpu_data_out;
			end if;
		end if;
	end if;
end process;

sn1 : entity work.sn76489_top
generic map (
	clock_div_16_g => 1
)
port map (
	clock_i    => clk,
	clock_en_i => ena_4,
	res_n_i    => not RESET,
	ce_n_i     => sn1_ce,
	we_n_i     => sn1_ce,
	ready_o    => sn1_ready,
	d_i        => sn_d,
	aout_o     => wav1s
);

sn2 : work.sn76489_top
generic map (
	clock_div_16_g => 1
)
port map (
	clock_i    => clk,
	clock_en_i => ena_4,
	res_n_i    => not RESET,
	ce_n_i     => sn2_ce,
	we_n_i     => sn2_ce,
	ready_o    => sn2_ready,
	d_i        => sn_d,
	aout_o     => wav2s
);

------------------------------------------

ay_we <= '1' when cpu_wr_l = '0' and cpu_iorq_l = '0' and cpu_addr(7 downto 1) = "0000011" else '0';

sn : ym2149
port map
(
	CLK 		=> clk,
	CE 		=> ENA_1M79,
	RESET 	=> reset,
	BDIR 		=> ay_we,
	BC 		=> cpu_addr(0),
	DI 		=> cpu_data_out,
	DO 		=> open,
	CHANNEL_A=> wav1u,
	CHANNEL_B=> wav2u,
	CHANNEL_C=> wav3u,

	SEL 		=> '0',
	MODE 		=> '0',
	IOA_in 	=> (others => '0'),
	IOA_out	=> open,

	IOB_in 	=> (others => '0'),
	IOB_out	=> open
);

------------------------------------------

O_AUDIO <= ("00" & wav1u) + ("00" & wav2u) + ("00" & wav3u)              when mod_dshop = '1'
		else (std_logic_vector(resize(wav1s, 9) + resize(wav2s, 9)) & '0') when mod_van = '1'
		else (wav4u & "00");

end RTL;
