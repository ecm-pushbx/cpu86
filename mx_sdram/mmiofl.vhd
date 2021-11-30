--***********************************************************
-- CPU86 SPI flash MMIO module
-- Module Name  : mmioflash
--***********************************************************

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;

entity mmioflash is
   port(
		  wb_cyc	: out std_logic;
		  wb_stb	: out std_logic;
		  cfg_stb: out std_logic;
		  wb_we	: out std_logic;
		  wb_addr: out std_logic_vector(21 downto 0);
		  i_wb_data		: out std_logic_vector(31 downto 0);
		  wb_stall		: in std_logic;
		  wb_ack			: in std_logic;
		  o_wb_data		: in std_logic_vector(31 downto 0);
		  abus   : in  std_logic_vector(3 downto 0);
		  clock	: in STD_LOGIC := '1';
		  clockmem		: in STD_LOGIC := '1';
		  data	: in STD_LOGIC_VECTOR(7 DOWNTO 0);
		  wren	: in STD_LOGIC;
        dbus   : out std_logic_vector(7 downto 0);
		  reset_n: in STD_LOGIC
);
end mmioflash;

architecture rtl of mmioflash is

signal flashdata : std_logic_vector(31 downto 0);
signal flashaddress : std_logic_vector(31 downto 0);
signal flashcontrol : std_logic_vector(7 downto 0);
signal flashduration : std_logic_vector(7 downto 0);
signal flash_next_is_data : std_logic;
signal priorclockmem : std_logic;

begin
 process(abus, clock, clockmem, wren, reset_n, flashcontrol, flash_next_is_data, wb_ack, o_wb_data)
  begin
		if (reset_n = '0') then
			flashdata <= X"00000000";
			flashaddress <= X"00000000";
			flashcontrol <= X"00";
			flashduration <= X"00";
			flash_next_is_data <= '0';
			wb_stb <= '0';
			wb_cyc <= '0';
			cfg_stb <= '0';
			i_wb_data <= X"00000000";
			priorclockmem <= '0';
		elsif rising_edge(clock) then
			if (flashcontrol(7) = '1') then
				if (flash_next_is_data = '1') then
					if (flashcontrol(6) = '0') then
						flashdata <= o_wb_data;
					end if;
					wb_stb <= '0';
					cfg_stb <= '0';
					wb_cyc <= '0';
					flashcontrol(6) <= '0';
					flashcontrol(7) <= '0';
					flash_next_is_data <= '0';
				elsif (wb_ack = '1') then
					flash_next_is_data <= '1';
				else
					flashduration <= std_logic_vector(unsigned(flashduration) + 1);
				end if;
			end if;
		if (clockmem = '0') then
			priorclockmem <= '0';
		end if;
		if (clockmem = '1' and priorclockmem = '0') then
			priorclockmem <= '1';
			if (wren='0') then
				case abus is
				 when "0000"  => dbus <= flashdata(7 downto 0);
             when "0001"  => dbus <= flashdata(15 downto 8);
             when "0010"  => dbus <= flashdata(23 downto 16);
             when "0011"  => dbus <= flashdata(31 downto 24);
             when "0100"  => dbus <= flashaddress(7 downto 0);
             when "0101"  => dbus <= flashaddress(15 downto 8);
             when "0110"  => dbus <= flashaddress(23 downto 16);
             when "0111"  => dbus <= flashaddress(31 downto 24);
             when "1000"  => dbus <= X"00";
             when "1001"  => dbus <= X"00";
             when "1010"  => dbus <= X"00";
             when "1011"  => dbus <= X"00";
             when "1100"  => dbus <= flashcontrol(7 downto 0);
             when "1101"  => dbus <= flashduration(7 downto 0);
             when "1110"  => dbus <= X"00";
             when "1111"  => dbus <= X"00";
             when others    => dbus <= "--------";
				end case;
			else -- wren='1'
				if (abus="1100") then
					if (data(0) = '1') then
						wb_addr <= flashaddress(21 downto 0);
						wb_we <= '0';
						wb_cyc <= '1';
						wb_stb <= '1';
						flashcontrol(7) <= '1';
						flashduration <= X"00";
					elsif (data(2) = '1') then
						wb_we <= '0';
						wb_cyc <= '1';
						cfg_stb <= '1';
						flashcontrol(7) <= '1';
						flashduration <= X"00";
					elsif (data(3) = '1') then
						i_wb_data(31 downto 16) <= (others => '0');
					   i_wb_data(15 downto 0) <= flashdata(15 downto 0);
						wb_we <= '1';
						wb_cyc <= '1';
						cfg_stb <= '1';
						flashcontrol(6) <= '1';
						flashcontrol(7) <= '1';
						flashduration <= X"00";
					end if;
				else
				case abus is
				 when "0000"  => flashdata(7 downto 0) <= data;
             when "0001"  => flashdata(15 downto 8) <= data;
             when "0010"  => flashdata(23 downto 16) <= data;
             when "0011"  => flashdata(31 downto 24) <= data;
             when "0100"  => flashaddress(7 downto 0) <= data;
             when "0101"  => flashaddress(15 downto 8) <= data;
             when "0110"  => flashaddress(23 downto 16) <= data;
             when "0111"  => flashaddress(31 downto 24) <= data;
             when "1000"  => null;
             when "1001"  => null;
             when "1010"  => null;
             when "1011"  => null;
             when "1100"  => null;
             -- when "1100"  => flashcontrol(7 downto 0) <= data;
             when "1101"  => null;
             when "1110"  => null;
             when "1111"  => null;
             when others    => null;
				end case;
				end if;
			end if;
			end if;
		end if;
end process;
end rtl;
