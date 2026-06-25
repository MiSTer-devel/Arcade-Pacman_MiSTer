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
-- version 004 Merge different variants by Alexey Melnikov
-- version 003 Jan 2006 release, general tidy up
-- version 001 initial release
--
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_unsigned.all;
	use ieee.numeric_std.all;

library UNISIM;

entity PACMAN_VIDEO is
port (
	I_HCNT            : in    std_logic_vector(8 downto 0);
	I_VCNT            : in    std_logic_vector(8 downto 0);
	--
	I_AB              : in    std_logic_vector(11 downto 0);
	I_DB              : in    std_logic_vector( 7 downto 0);
	--
	I_HBLANK          : in    std_logic;
	I_VBLANK          : in    std_logic;
	I_FLIP            : in    std_logic;
	I_WR2_L           : in    std_logic;
	--
	dn_addr           : in  std_logic_vector(15 downto 0);
	dn_data           : in  std_logic_vector(7 downto 0);
	dn_wr             : in  std_logic;
	--
	O_RED             : out   std_logic_vector(2 downto 0);
	O_GREEN           : out   std_logic_vector(2 downto 0);
	O_BLUE            : out   std_logic_vector(1 downto 0);
	MRTNT             : in    std_logic := '0';  -- 1 to descramble Mr TNT ROMs, 0 otherwise
	PONP              : in    std_logic := '0';
	ENA_6             : in    std_logic;
	CLK               : in    std_logic;

	flip_screen       : in    std_logic;

	-- Jr. Pac-Man (gated by mod_jr; defaults keep non-Jr instantiations valid)
	mod_jr            : in    std_logic := '0';
	jr_scroll         : in    std_logic_vector(7 downto 0) := (others => '0');
	jr_charbank       : in    std_logic := '0';
	jr_spritebank     : in    std_logic := '0';
	jr_palbank        : in    std_logic := '0';
	jr_colortabbank   : in    std_logic := '0';
	jr_bgpriority     : in    std_logic := '0';
	jr_hud            : in    std_logic := '0'   -- '1' = HUD/non-scrolling column; '0' = scrolling playfield (for sub-tile scroll)
);
end;

architecture RTL of PACMAN_VIDEO is

	signal sprite_xy_ram_temp : std_logic_vector(7 downto 0);
	signal dr                 : std_logic_vector(7 downto 0);
	signal xy                 : std_logic_vector(7 downto 0);

	signal char_reg           : std_logic_vector(7 downto 0);
	signal char_sum_reg       : std_logic_vector(3 downto 0);
	signal char_match_reg     : std_logic;
	signal char_hblank_reg    : std_logic;
	signal char_hblank_reg_t1 : std_logic;
	signal db_reg             : std_logic_vector(7 downto 0);

	signal xflip              : std_logic;
	signal yflip              : std_logic;
	signal obj_on             : std_logic;

	signal cax                : std_logic_vector(1 downto 0);
	signal ca                 : std_logic_vector(13 downto 0);  -- 14-bit for Jr (16KB gfx); bit13=0 for non-Jr
	signal char_rom_5ef_dout  : std_logic_vector(7 downto 0);
	signal char_rom_5ef_buf   : std_logic_vector(7 downto 0);

	signal shift_regl         : std_logic_vector(3 downto 0);
	signal shift_regu         : std_logic_vector(3 downto 0);
	signal shift_op           : std_logic_vector(1 downto 0);
	signal shift_op_t1        : std_logic_vector(1 downto 0);
	signal shift_sel          : std_logic_vector(1 downto 0);

	signal vout_obj_on        : std_logic;
	signal vout_obj_on_t1     : std_logic;
	signal vout_yflip         : std_logic;
	signal vout_hblank        : std_logic;
	signal vout_hblank_t1     : std_logic;
	signal vout_db            : std_logic_vector(4 downto 0);

	signal cntr_ld            : std_logic;
	signal sprite_ram_ip      : std_logic_vector(5 downto 0);
	signal sprite_ram_op      : std_logic_vector(5 downto 0);
	signal ra                 : std_logic_vector(7 downto 0);
	signal ra_t1              : std_logic_vector(7 downto 0);

	signal lut_4a             : std_logic_vector(7 downto 0);
	signal lut_4a_t1          : std_logic_vector(7 downto 0);
	signal sprite_ram_reg     : std_logic_vector(5 downto 0);

	signal video_op_sel       : std_logic;
	signal final_col          : std_logic_vector(4 downto 0);  -- Jr: bit4 = palettebank

	signal gfx_cs             : std_logic;
	signal prom_cs            : std_logic;
	signal rom7_cs            : std_logic;
	signal rom4a_cs           : std_logic;
	-- Jr. Pac-Man gfx load (16KB)
	signal jr_gfx_cs          : std_logic;
	signal gfx_we             : std_logic;
	signal gfx_waddr          : std_logic_vector(13 downto 0);
	signal jr_gfx_waddr       : std_logic_vector(15 downto 0);
	-- Jr. Pac-Man colour path
	signal jr_clut_cs         : std_logic;
	signal jr_pal_lo_cs       : std_logic;
	signal jr_pal_hi_cs       : std_logic;
	signal clut_a7            : std_logic;
	signal pm_rgb             : std_logic_vector(7 downto 0);
	signal jr_pal_lo_q        : std_logic_vector(7 downto 0);
	signal jr_pal_hi_q        : std_logic_vector(7 downto 0);
	signal rgb_out            : std_logic_vector(7 downto 0);

begin

	prom_cs <= '1' when dn_addr(15 downto 14) = "11" else '0';
	gfx_cs  <= '1' when dn_addr(15 downto 13) = "100" else '0';
	-- Jr. Pac-Man: gfx loads linearly — tiles dn A000-BFFF -> char ROM 0x0000-1FFF, sprites dn C000-DFFF -> 0x2000-3FFF.
	jr_gfx_cs    <= '1' when mod_jr='1' and dn_addr >= x"A000" and dn_addr < x"E000" else '0';
	jr_gfx_waddr <= dn_addr - x"A000";
	gfx_we       <= (dn_wr and jr_gfx_cs) when mod_jr='1' else (dn_wr and gfx_cs);
	gfx_waddr    <= jr_gfx_waddr(13 downto 0) when mod_jr='1' else ('0' & dn_addr(12 downto 0));

	-- invert sprite position when flip_screen mode is enabled. offset x positions
	xy <= not sprite_xy_ram_temp when flip_screen = '0' else sprite_xy_ram_temp - 19 when I_AB(0) = '1' else sprite_xy_ram_temp - 15 + to_integer(unsigned'("" & (not (I_AB(1) and I_AB(2)) xor I_AB(3)) & "0"));

	-- ram enable is low when HBLANK_L is 0 (for sprite access) or
	-- 2H is low (for cpu writes)
	-- we can simplify this
	dr <= xy when I_HBLANK = '1' else "11111111"; -- pull ups on board

	sprite_xy_ram : work.dpram generic map (4,8)
	port map
	(
		clock_a   => CLK,
		enable_a  => ENA_6,
		wren_a    => not I_WR2_L,
		address_a => I_AB(3 downto 0),
		data_a    => I_DB,

		clock_b   => CLK,
		address_b => I_AB(3 downto 0),
		q_b       => sprite_xy_ram_temp
	);

	p_char_regs : process
		variable inc : std_logic;
		variable sum : std_logic_vector(8 downto 0);
		variable sum_line : std_logic_vector(8 downto 0);  -- Jr smooth-scroll: within-tile vertical line w/ jr_scroll added (playfield only)
		variable match : std_logic;
	begin
		wait until rising_edge (CLK);
		if (I_HCNT(2 downto 0) = "011") and (ENA_6 = '1') then  -- rising 4h
			inc := (not I_HBLANK);

			-- 1f, 2f
			sum := (I_VCNT(7 downto 0) & '1') + (dr & inc);

			-- Jr. Pac-Man SMOOTH (sub-tile) scroll. The COARSE tile row already includes jr_scroll (pacman.vhd jr_mr);
			-- add the SAME scroll to the WITHIN-tile vertical line here so the playfield moves 1px/step, not 8px (blocky).
			-- Gates: I_HBLANK='0' keeps sprite-Y matching + 'match' on the UNscrolled counter (sprites stay put);
			--        jr_hud='0' keeps the HUD score rows (non-scrolling cols) from shearing. Non-Jr untouched.
			if (mod_jr = '1' and jr_hud = '0' and I_HBLANK = '0') then
				sum_line := ((I_VCNT(7 downto 0) + jr_scroll) & '1') + (dr & inc);
			else
				sum_line := sum;
			end if;

			-- 3e
			match := '0';

			if (sum(8 downto 5) = "1111") then
			  match := '1';
			end if;

			-- 1h
			char_sum_reg     <= sum_line(4 downto 1);  -- was sum(4 downto 1); sum_line carries Jr sub-tile scroll
			char_match_reg   <= match;
			char_hblank_reg  <= I_HBLANK;

			-- 4d
			db_reg <= I_DB; -- character reg
		end if;
	end process;

	p_flip_comb : process(char_hblank_reg, I_FLIP, db_reg, flip_screen)
	begin
		if (char_hblank_reg = '0') then
			xflip     <= I_FLIP;
			yflip     <= I_FLIP;
		else
			xflip     <= db_reg(1) xor flip_screen;
			yflip     <= db_reg(0) xor flip_screen;
		end if;
	end process;

	cax(1) <= db_reg(0) when char_hblank_reg = '0' else I_HCNT(3);
	cax(0) <= I_HCNT(2) xor yflip;

	p_char_addr_comb : process(db_reg, I_HCNT,
										char_match_reg, char_sum_reg, char_hblank_reg,
										xflip, yflip, MRTNT, PONP, cax,
										mod_jr, jr_charbank, jr_spritebank)
	begin
		obj_on <= char_match_reg or I_HCNT(8); -- 256h not 256h_l

		-- Jr: 16KB gfx — region (tile/sprite) moves to ca(13); ca(12)=bank (char/sprite). Pac-Man: ca(13)=0, ca(12)=region.
		if mod_jr = '1' then
			ca(13) <= char_hblank_reg;
			if char_hblank_reg = '0' then
				ca(12) <= jr_charbank;
			else
				ca(12) <= jr_spritebank;
			end if;
		else
			ca(13) <= '0';
			ca(12) <= char_hblank_reg;
		end if;
		ca(11 downto 6) <= db_reg(7 downto 2);

		-- 2h, 4e
		if (char_hblank_reg = '0') then
			ca(5)     <= db_reg(1);
			ca(4)     <= db_reg(0);
		else
			ca(5)     <= char_sum_reg(3) xor xflip;
			ca(4)     <= I_HCNT(3);
		end if;

		ca(3) <= I_HCNT(2)       xor yflip;
		ca(1) <= char_sum_reg(1) xor xflip;

		if PONP = '1' then
			if char_hblank_reg='0' then
				ca(4 downto 3) <= cax(1) & not cax(0);
			else
				ca(4 downto 3) <= cax - "1";
			end if;
		end if;

		-- descramble ROMs for Mr TNT (swap address lines A0 and A2)
		if MRTNT = '1' then
			ca(2) <= char_sum_reg(0) xor xflip;
			ca(0) <= char_sum_reg(2) xor xflip;
		else
			ca(2) <= char_sum_reg(2) xor xflip;
			ca(0) <= char_sum_reg(0) xor xflip;
		end if;
	end process;


	-- descramble ROMs for Mr TNT (swap data lines D4 and D6)
	char_rom_5ef_dout <= char_rom_5ef_buf(7) & char_rom_5ef_buf(4) & char_rom_5ef_buf(5) & char_rom_5ef_buf(6) & char_rom_5ef_buf(3 downto 0) when MRTNT = '1' else char_rom_5ef_buf;

	-- char roms
	char_rom_5ef : work.dpram generic map (14,8)
	port map
	(
		clock_a   => clk,
		wren_a    => gfx_we,
		address_a => gfx_waddr,
		data_a    => dn_data,

		clock_b   => clk,
		address_b => ca,
		q_b       => char_rom_5ef_buf
	);

	p_char_shift : process
	begin
		-- 4 bit shift req
		wait until rising_edge (CLK);
		if (ENA_6 = '1') then
			case shift_sel is
				when "00" =>	null;

				when "01" =>	shift_regu <= '0' & shift_regu(3 downto 1);
									shift_regl <= '0' & shift_regl(3 downto 1);

				when "10" =>	shift_regu <= shift_regu(2 downto 0) & '0';
									shift_regl <= shift_regl(2 downto 0) & '0';

				when "11" =>	shift_regu <= char_rom_5ef_dout(7 downto 4); -- load
									shift_regl <= char_rom_5ef_dout(3 downto 0);
				when others => null;
			end case;
		end if;
	end process;

	p_char_shift_comb : process(I_HCNT, vout_yflip, shift_regu, shift_regl)
		variable ip : std_logic;
	begin
		ip := I_HCNT(0) and I_HCNT(1);
		if (vout_yflip = '0') then

			shift_sel(0) <= ip;
			shift_sel(1) <= '1';
			shift_op(0) <= shift_regl(3);
			shift_op(1) <= shift_regu(3);
		else

			shift_sel(0) <= '1';
			shift_sel(1) <= ip;
			shift_op(0) <= shift_regl(0);
			shift_op(1) <= shift_regu(0);
		end if;
	end process;

	p_video_out_reg : process
	begin
		wait until rising_edge (CLK);
		if (ENA_6 = '1') then
			if (I_HCNT(2 downto 0) = "111") then
				vout_obj_on   <= obj_on;
				vout_yflip    <= yflip;
				vout_hblank   <= I_HBLANK;
				vout_db(4 downto 0) <= I_DB(4 downto 0); -- colour reg
			end if;
		end if;
	end process;

	rom4a_cs <= '1' when dn_addr(9 downto 8) = "01" else '0';
	-- Jr: colour-lookup PROM (9p) at dn E200-E2FF; CLUT address top bit = colortablebank.
	jr_clut_cs <= '1' when mod_jr='1' and dn_addr(15 downto 8) = x"E2" else '0';
	clut_a7    <= jr_colortabbank when mod_jr='1' else '0';

	col_rom_4a : work.dpram generic map (8,8)
	port map
	(
		clock_a   => CLK,
		wren_a    => dn_wr and ((rom4a_cs and prom_cs) or jr_clut_cs),
		address_a => dn_addr(7 downto 0),
		data_a    => dn_data,
	
		clock_b   => CLK,
		address_b(7)          => clut_a7,
		address_b(6 downto 2) => vout_db(4 downto 0),
		address_b(1 downto 0) => shift_op(1 downto 0),
		q_b       => lut_4a
	);


	cntr_ld <= '1' when (I_HCNT(3 downto 0) = "0111") and (vout_hblank='1' or I_HBLANK='1' or vout_obj_on='0') else '0';

	p_ra_cnt : process
	begin
		wait until rising_edge (CLK);
		if (ENA_6 = '1') then
			if (cntr_ld = '1') then
				ra <= dr;
			else
				ra <= ra + "1";
			end if;
		end if;
	end process;

	u_sprite_ram : work.dpram generic map (8,6)
	port map
	(
		clock_a   => CLK,
		enable_a  => ENA_6,
		wren_a    => vout_obj_on_t1,
		address_a => ra_t1,
		data_a    => sprite_ram_ip,
	
		clock_b   => CLK,
		enable_b  => ENA_6,
		address_b => ra,
		q_b       => sprite_ram_op
	);

	sprite_ram_reg <= sprite_ram_op when vout_obj_on_t1 = '1' else "000000";
	video_op_sel <= '1' when not (sprite_ram_reg(5 downto 2) = "0000") else '0';

	p_sprite_ram_ip_reg : process
	begin
		wait until rising_edge (CLK);
		if (ENA_6 = '1') then
			ra_t1 <= ra;
			vout_obj_on_t1 <= vout_obj_on;
			vout_hblank_t1 <= vout_hblank;
			lut_4a_t1 <= lut_4a;
			shift_op_t1 <= shift_op;
		end if;
	end process;

	p_sprite_ram_ip_comb : process(vout_hblank_t1, video_op_sel, sprite_ram_reg, lut_4a_t1, shift_op_t1)
	begin
	-- 3a
		if (vout_hblank_t1 = '0') then
			sprite_ram_ip <= (others => '0');
		else
			if (video_op_sel = '1') then
				sprite_ram_ip <= sprite_ram_reg;
			else
				sprite_ram_ip <= lut_4a_t1(3 downto 0) & shift_op_t1;
			end if;
		end if;
	end process;

	p_video_op_comb : process(vout_hblank, I_VBLANK, video_op_sel, sprite_ram_reg, lut_4a, jr_palbank, jr_bgpriority, mod_jr)
	begin
		-- 3b ; Jr: bit4 = palettebank. bgpriority=1 => tiles draw OVER sprites (tile pen!=0 wins; else sprite; else black).
		if (vout_hblank = '1') or (I_VBLANK = '1') then
			final_col <= (others => '0');
		elsif (mod_jr = '1' and jr_bgpriority = '1') then
			if (lut_4a(3 downto 0) /= "0000") then
				final_col <= jr_palbank & lut_4a(3 downto 0);          -- tile over sprite
			elsif (video_op_sel = '1') then
				final_col <= jr_palbank & sprite_ram_reg(5 downto 2);  -- sprite where tile transparent
			else
				final_col <= (others => '0');                          -- black background
			end if;
		else
			if (video_op_sel = '1') then
				final_col <= (jr_palbank and mod_jr) & sprite_ram_reg(5 downto 2); -- sprite
			else
				final_col <= (jr_palbank and mod_jr) & lut_4a(3 downto 0);
			end if;
		end if;
	end process;

	-- assign video outputs from color LUT PROM
	rom7_cs <= '1' when dn_addr(9 downto 4) = "110000" else '0';

	-- Pac-Man base palette (widened to 32 so Jr's 5-bit final_col fits; Pac-Man loads 16, never addresses >15).
	col_rom_7f : work.dpram generic map (5,8)
	port map
	(
		clock_a   => CLK,
		wren_a    => dn_wr and rom7_cs and prom_cs,
		address_a => '0' & dn_addr(3 downto 0),
		data_a    => dn_data,

		clock_b   => CLK,
		address_b => final_col,
		q_b       => pm_rgb
	);

	-- Jr base palette (32 colours, RRRGGGBB) from 9e (low nibble, dn E000) + 9f (high nibble, dn E100).
	jr_pal_lo_cs <= '1' when mod_jr='1' and dn_addr(15 downto 8) = x"E0" else '0';
	jr_pal_hi_cs <= '1' when mod_jr='1' and dn_addr(15 downto 8) = x"E1" else '0';

	jr_pal_lo : work.dpram generic map (8,8)
	port map (
		clock_a => CLK, wren_a => dn_wr and jr_pal_lo_cs, address_a => dn_addr(7 downto 0), data_a => dn_data,
		clock_b => CLK, address_b => "000" & final_col, q_b => jr_pal_lo_q );

	jr_pal_hi : work.dpram generic map (8,8)
	port map (
		clock_a => CLK, wren_a => dn_wr and jr_pal_hi_cs, address_a => dn_addr(7 downto 0), data_a => dn_data,
		clock_b => CLK, address_b => "000" & final_col, q_b => jr_pal_hi_q );

	rgb_out <= (jr_pal_hi_q(3 downto 0) & jr_pal_lo_q(3 downto 0)) when mod_jr = '1' else pm_rgb;
	O_RED   <= rgb_out(2 downto 0);
	O_GREEN <= rgb_out(5 downto 3);
	O_BLUE  <= rgb_out(7 downto 6);

end architecture;
