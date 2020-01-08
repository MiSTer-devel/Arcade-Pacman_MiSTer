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
	O_AUDIO    : out std_logic_vector(7 downto 0);
	--
	in0        : in  std_logic_vector(7 downto 0);
	in1        : in  std_logic_vector(7 downto 0);
	dipsw      : in  std_logic_vector(7 downto 0);
	dipsw2     : in  std_logic_vector(7 downto 0);
	--
	mod_plus   : in  std_logic;
	mod_bird   : in  std_logic;
	mod_mrtnt  : in  std_logic;
	mod_ms     : in  std_logic;
	mod_woodp  : in  std_logic;
	mod_eeek   : in  std_logic;
	mod_alib   : in  std_logic;
	mod_ponp   : in  std_logic;
	mod_van    : in  std_logic;
	--
	dn_addr    : in  std_logic_vector(15 downto 0);
	dn_data    : in  std_logic_vector(7 downto 0);
	dn_wr      : in  std_logic;
	--
	RESET      : in  std_logic;
	CLK        : in  std_logic;
	ENA_6      : in  std_logic;
	ENA_4      : in  std_logic
);
end;

architecture RTL of PACMAN is


    -- timing
    signal hcnt             : std_logic_vector(8 downto 0) := "010000000"; -- 80
    signal vcnt             : std_logic_vector(8 downto 0) := "011111000"; -- 0F8

    signal do_hsync         : boolean;
    signal hsync            : std_logic;
    signal vsync            : std_logic;
    signal hblank           : std_logic;
    signal vblank           : std_logic := '1';

    -- cpu
    signal cpu_ena          : std_logic;
    signal cpu_m1_l         : std_logic;
    signal cpu_mreq_l       : std_logic;
    signal cpu_iorq_l       : std_logic;
    signal cpu_rd_l         : std_logic;
    signal cpu_wr_l         : std_logic;
    signal cpu_rfsh_l       : std_logic;
    signal cpu_wait_l       : std_logic;
    signal cpu_int_l        : std_logic;
    signal cpu_addr         : std_logic_vector(15 downto 0);
    signal cpu_data_out     : std_logic_vector(7 downto 0);
    signal cpu_data_in      : std_logic_vector(7 downto 0);

    signal ram_we           : std_logic;
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

    signal vram_l           : std_logic;
    signal rams_data_out    : std_logic_vector(7 downto 0);
    -- more decode
    signal wr0_l            : std_logic;
    signal wr1_l            : std_logic;
    signal wr2_l            : std_logic;
    signal iodec_out_l      : std_logic;
    signal iodec_wdr_l      : std_logic;
    signal iodec_in0_l      : std_logic;
    signal iodec_in1_l      : std_logic;
    signal iodec_dipsw_l    : std_logic;
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
    signal wav1,wav2        : signed(7 downto 0);
    signal wav3             : signed(8 downto 0);
	 signal wav4             : std_logic_vector(7 downto 0);

begin

  --
  -- video timing
  --
  p_hvcnt : process
    variable hcarry,vcarry : boolean;
  begin
    wait until rising_edge(clk);
    if (ena_6 = '1') then
      hcarry := (hcnt = "111111111");
      if hcarry then
        hcnt <= "010000000"; -- 080
      else
        hcnt <= hcnt +"1";
      end if;
      -- hcnt 8 on circuit is 256H_L
      vcarry := (vcnt = "111111111");
      if do_hsync then
        if vcarry then
          vcnt <= "011111000"; -- 0F8
        else
          vcnt <= vcnt +"1";
        end if;
      end if;
    end if;
  end process;

  p_sync_comb : process(hcnt, vcnt)
  begin
    vsync <= not vcnt(8);
    do_hsync <= (hcnt = "010101111"); -- 0AF
  end process;

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

      if do_hsync then
        hsync <= '1';
      elsif (hcnt = "011001111") then -- 0CF
        hsync <= '0';
      end if;

      if do_hsync then
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
  p_cpu_wait_comb : process(sync_bus_wreq_l)
  begin
    cpu_wait_l  <= '1';
    if (sync_bus_wreq_l = '0') then
      cpu_wait_l  <= '0';
    end if;
  end process;

  p_irq_req_watchdog : process
    variable rising_vblank : boolean;
  begin
    wait until rising_edge(clk);
    if (ena_6 = '1') then
      rising_vblank := do_hsync and (vcnt = "111101111"); -- 1EF
      --rising_vblank := do_hsync; -- debug
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
      elsif rising_vblank then
        watchdog_cnt <= watchdog_cnt + "1";
      end if;

      watchdog_reset_l <= '1';
		if (watchdog_cnt = X"FF") then
        watchdog_reset_l <= '0';
      end if;
    end if;
  end process;

  p_cpu_ena : process(hcnt, ena_6)
  begin
    cpu_ena <= '0';
    if (ena_6 = '1') then
      cpu_ena <= hcnt(0);
    end if;
  end process;

  u_cpu : entity work.T80sed
          port map (
              RESET_n => watchdog_reset_l,
              CLK_n   => clk,
              CLKEN   => cpu_ena,
              WAIT_n  => cpu_wait_l,
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
  p_mem_decode_comb : process(cpu_rfsh_l, cpu_rd_l, cpu_mreq_l, cpu_addr)
  begin
    -- rom     0x0000 - 0x3FFF
    -- syncbus 0x4000 - 0x7FFF

    -- 7M
    -- 7N
    sync_bus_cs_l <= '1';
--    program_rom_cs_l  <= '1';

    if (cpu_mreq_l = '0') and (cpu_rfsh_l = '1') then

--      if (cpu_addr(14) = '0') and (cpu_rd_l = '0') then
--         program_rom_cs_l <= '0';
--      end if;

      if (cpu_addr(14) = '1') then
         sync_bus_cs_l <= '0';
      end if;

    end if;
  end process;
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

  p_sync_bus_comb : process(cpu_rd_l, sync_bus_cs_l, hcnt)
  begin
    -- sync_bus_stb is now an active low clock enable signal
    sync_bus_stb <= '1';
    sync_bus_r_w_l <= '1';

    if (sync_bus_cs_l = '0') and (hcnt(1) = '0') then
      if (cpu_rd_l = '1') then
        sync_bus_r_w_l <= '0';
      end if;
      sync_bus_stb <= '0';
    end if;

    sync_bus_wreq_l <= '1';
    if (sync_bus_cs_l = '0') and (hcnt(1) = '1') and (cpu_rd_l = '0') then
      sync_bus_wreq_l <= '0';
    end if;
  end process;
  --
  -- vram addr custom ic
  --
  u_vram_addr : entity work.PACMAN_VRAM_ADDR
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
	vram_addr <= vram_addr_ab when mod_alib = '0' and mod_ponp = '0' else '0' & hcnt(2) & vp & hp when hcnt(8)='1' else
             x"FF" & hcnt(6 downto 4) & hcnt(2) when hblank = '1' and mod_ponp = '1' else
             x"EF" & hcnt(6 downto 4) & hcnt(2) when hblank = '1' else
             '0' & hcnt(2) & hp(3) & hp(3) & hp(3) & hp(3) & hp(0) & vp;

  p_ab_mux_comb : process(hcnt, cpu_addr, vram_addr)
  begin
    --When 2H is low, the CPU controls the bus.
    if (hcnt(1) = '0') then
      ab <= cpu_addr(11 downto 0);
    else
      ab <= vram_addr;
    end if;
  end process;

  p_vram_comb : process(hcnt, cpu_addr, sync_bus_stb)
    variable a,b : std_logic;
  begin

    a := not (cpu_addr(12) or sync_bus_stb);
    b := hcnt(1) and hcnt(0);
    vram_l <= not (a or b);
  end process;

  iodec_01 <= '1' when cpu_addr(5 downto 1) = "00000" else '0';

  p_io_decode_comb : process(sync_bus_r_w_l, sync_bus_stb, ab, cpu_addr, mod_bird, mod_alib, iodec_01)
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
    iodec_dipsw_l <= dec(6);
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
	 if mod_alib = '1' then
		wr2_l <= decb(1);
		wr1_l <= decb(2);
	 else
		wr1_l <= decb(1);
		wr2_l <= decb(2);
	 end if;
  end process;

  p_control_reg : process
    variable ena : std_logic_vector(7 downto 0);
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
      ena := "00000000";
      if (iodec_out_l = '0') then
        case ab(2 downto 0) is
          when "000" => ena := "00000001";
          when "001" => ena := "00000010";
          when "010" => ena := "00000100";
          when "011" => ena := "00001000";
          when "100" => ena := "00010000";
          when "101" => ena := "00100000";
          when "110" => ena := "01000000";
          when "111" => ena := "10000000";
          when others => null;
        end case;
      end if;

      if (watchdog_reset_l = '0') then
        control_reg <= (others => '0');
      else
        for i in 0 to 7 loop
          if (ena(i) = '1') then
            control_reg(i) <= cpu_data_out(0);
          end if;
        end loop;
      end if;
    end if;
  end process;
  
  c_flip <= control_reg(1) when mod_alib = '1' else control_reg(5) when mod_bird = '1' else control_reg(3);
  c_sound<= control_reg(0) when mod_alib = '1' else control_reg(3) when mod_bird = '1' else control_reg(1);
  c_int  <= control_reg(2) when mod_alib = '1' else control_reg(1) when mod_bird = '1' else control_reg(0);

  p_db_mux_comb : process(hcnt, cpu_data_out, rams_data_out)
  begin
    -- simplified data source for video subsystem
    -- only cpu or ram are sources of interest
    if (hcnt(1) = '0') then
      sync_bus_db <= cpu_data_out;
    else
      sync_bus_db <= rams_data_out;
    end if;
  end process;
  
  p_mcnt : process
  begin
    wait until rising_edge(clk);
    mcnt <= (mcnt + "1") + ("0000000" & (in0(3) xor in0(2) xor in0(1) xor in0(0)));
  end process;

  p_mcnt2 : process
  begin
  	 wait until rising_edge(clk);
  	 if (ena_6 = '1') then
		old_rd_l2 <= cpu_rd_l;
  		if iodec_myst2_l = '0' and old_rd_l2 = '1' and cpu_rd_l = '0' then
  			mcnt2 <= mcnt2 + "1";
  		end if;
  	 end if;
  end process;
  

  inj <= in0(3 downto 0) when control_reg(5 downto 4) = "01" else
         in1(3 downto 0) when control_reg(5 downto 4) = "10" else
         in0(3 downto 0) and in1(3 downto 0);

  p_cpu_data_in_mux_comb : process(cpu_addr, cpu_iorq_l, cpu_m1_l, sync_bus_wreq_l,
                                   iodec_in0_l, iodec_in1_l, iodec_dipsw_l, cpu_vec_reg, sync_bus_reg, rom_data,
											  rams_data_out, in0, in1, dipsw, inj, iodec_dipsw2_l, dipsw2,
											  ram2_cs, ram2_data, iodec_myst1_l, iodec_myst2_l, mcnt, mcnt2, iodec_nop_l)
  begin
    -- simplifed again
    if (cpu_iorq_l = '0') and (cpu_m1_l = '0') then
      cpu_data_in <= cpu_vec_reg;
    elsif (sync_bus_wreq_l = '0') then
      cpu_data_in <= sync_bus_reg;
    else
		if ram2_cs = '1' then
		  cpu_data_in <= ram2_data;
      elsif (cpu_addr(14) = '0') then      -- ROM at 0000 - 3fff, 8000 - bfff
        cpu_data_in <= rom_data;
      else
        cpu_data_in <= rams_data_out;
        if (iodec_in0_l   = '0') then cpu_data_in <= in0(7 downto 4) & inj; end if;
        if (iodec_in1_l   = '0') then cpu_data_in <= in1; end if;
        if (iodec_dipsw_l = '0') then cpu_data_in <= dipsw; end if;
        if (iodec_dipsw2_l= '0') then cpu_data_in <= dipsw2; end if;
        if (iodec_myst1_l = '0') then cpu_data_in <= "0000" & mcnt(3 downto 0); end if;
        if (iodec_myst2_l = '0') then cpu_data_in <= "0000000" & mcnt2(10); end if;
        if (iodec_nop_l   = '0') then cpu_data_in <= x"BF"; end if;
      end if;
    end if;
  end process;

  u_rams : work.dpram generic map (12,8)
  port map
  (
  	 clock_a   => clk,
  	 enable_a  => ena_6,
  	 wren_a    => not sync_bus_r_w_l and not vram_l,
  	 address_a => ab(11 downto 0),
  	 data_a    => cpu_data_out, -- cpu only source of ram data
  	 clock_b   => clk,
  	 address_b => ab(11 downto 0),
  	 q_b       => rams_data_out
  );

  ram_we  <= '1' when cpu_wr_l = '0' and cpu_mreq_l = '0' and cpu_rfsh_l = '1' else '0';
  ram2_cs <= '1' when cpu_addr(15 downto 12) = X"9" and mod_alib = '1' else '0';

  u_ram2 : work.dpram generic map (10,8)
  port map
  (
    clock_a   => clk,
    enable_a  => ena_6,
    wren_a    => ram_we and ram2_cs,
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
  		dcnt <= "01";
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
  	 PLUS     => mod_plus,
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
  u_video : entity work.PACMAN_VIDEO
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
      CLK       => clk
      );

      O_HSYNC   <= hSync;
      O_VSYNC   <= vSync;

      --O_HBLANK  <= hblank;
      O_VBLANK  <= vblank;

  --
  --
  -- audio subsystem
  --
  u_audio : entity work.PACMAN_AUDIO
    port map (
      I_HCNT        => hcnt,
      --
      I_AB          => ab,
      I_DB          => sync_bus_db,
      --
      I_WR1_L       => wr1_l,
      I_WR0_L       => wr0_l,
      I_SOUND_ON    => c_sound,
      --
      dn_addr       => dn_addr,
      dn_data       => dn_data,
      dn_wr         => dn_wr,
      --		
      O_AUDIO       => wav4,
      ENA_6         => ena_6,
      CLK           => clk
      );

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
		aout_o     => wav1
	);
	
	sn2 : entity work.sn76489_top
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
		aout_o     => wav2
	);
	
	wav3 <= resize(wav1, 9) + resize(wav2, 9);

	O_AUDIO <= wav4 when mod_van = '0' else std_logic_vector(wav3(8 downto 1));
end RTL;
