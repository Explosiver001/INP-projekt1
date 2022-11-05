-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0) := (others => '0'); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  signal cnt_inc: std_logic := '0';
  signal cnt_dec: std_logic := '0';
  signal cnt_state: std_logic_vector(12 downto 0) := (others => '0');

  signal pc_inc: std_logic := '0';
  signal pc_dec: std_logic := '0';
  signal pc_state: std_logic_vector(12 downto 0) := (others => '0');

  signal ptr_inc: std_logic := '0';
  signal ptr_dec: std_logic := '0';
  signal ptr_state: std_logic_vector(12 downto 0) := "1000000000000";


  signal mx1_out: std_logic_vector(12 downto 0) := (others => '0');
  signal mx2_out: std_logic_vector(7 downto 0) := (others => '0');

  signal mx1_sel: std_logic := '0';
  signal mx2_sel: std_logic_vector(1 downto 0);


  -- Stavy FSM 
  type fsm_state is (
    fsm_start,
		fsm_fetch,
    fsm_decode, 
    fsm_pointer_inc,                                        --  >   || 0x3E ||inkrementace hodnoty ukazatele
    fsm_pointer_dec,                                        --  <   || 0x3C ||dekrementace hodnoty ukazatele
    fsm_value_inc0, fsm_value_inc1, fsm_value_inc2, fsm_value_inc3,        --  +   || 0x2B ||inkrementace hodnoty aktualni bunky
    fsm_value_dec0, fsm_value_dec1, fsm_value_dec2, fsm_value_dec3,                                          --  -   || 0x2D ||dekrementace hodnoty aktualni bunky
    fsm_while_begin,                                        --  [   || 0x5B ||zacatek while cyklu
    fsm_while_end,                                          --  ]   || 0x5D ||konec while cyklu
    fsm_do_while_begin,                                     --  (   || 0x28 ||zacatek do-while cyklu
    fsm_do_while_end,                                       --  )   || 0x29 ||konec do-while cyklu
    fsm_print_value0, fsm_print_value1, fsm_print_value2, fsm_print_value3, fsm_print_value4,                                        --  .   || 0x2E ||vytiskni aktualni hodnotu bunky
    fsm_get_value0, fsm_get_value1, fsm_get_value2,                                         --  ,   || 0x2C ||nacti hodnotu a uloz do aktualni bunky
    fsm_null                                                -- null || 0x00 ||zastav vykonavani programu
  );

  signal actual_state : fsm_state := fsm_start;
  signal next_state : fsm_state := fsm_start;

begin -- architecture


  fsm_state_logic_proc: process(CLK, RESET, EN)
  begin
      if RESET = '1' then
        actual_state <= fsm_start;
      elsif rising_edge(CLK) then
        if EN = '1' then
          actual_state <= next_state;
        end if;
      end if;
  end process;

  fsm_proc: process (actual_state, OUT_BUSY, IN_VLD, DATA_RDATA, cnt_state)
  begin
    -- init --
    cnt_inc <= '0';
    cnt_dec <= '0';
    pc_inc <= '0';
    pc_dec <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';
    mx1_sel <= '0';
    mx2_sel <= "11";
    DATA_EN <= '0';
    DATA_RDWR <= '0';
    IN_REQ <= '0';
    OUT_WE <= '0';

    case actual_state is
      when fsm_start =>
              next_state <= fsm_fetch;


      when fsm_fetch =>
              DATA_EN <= '1';
              next_state <= fsm_decode;

      
      when fsm_decode =>
              case DATA_RDATA is
                when X"3E" => --  >   || 0x3E ||inkrementace hodnoty ukazatele
                  next_state <= fsm_pointer_inc;
                when X"3C" => --  <   || 0x3C ||dekrementace hodnoty ukazatele
                  next_state <= fsm_pointer_dec;
                when X"2B" => --  +   || 0x2B ||inkrementace hodnoty aktualni bunky
                  next_state <= fsm_value_inc0;
                when X"2D" => --  -   || 0x2D ||dekrementace hodnoty aktualni bunky
                  next_state <= fsm_value_dec0;
                when X"5B" => --  [   || 0x5B ||zacatek while cyklu
                  next_state <= fsm_while_begin;
                when X"5D" => --  ]   || 0x5D ||konec while cyklu
                  next_state <= fsm_while_end;
                when X"28" => --  (   || 0x28 ||zacatek do-while cyklu
                  next_state <= fsm_do_while_begin;
                when X"29" => --  )   || 0x29 ||konec do-while cyklu
                  next_state <= fsm_do_while_end;
                when X"2E" => --  .   || 0x2E ||vytiskni aktualni hodnotu bunky
                  next_state <= fsm_print_value0;
                when X"2C" => --  ,   || 0x2C ||nacti hodnotu a uloz do aktualni bunky
                  next_state <= fsm_get_value0;
                when X"00" => -- null || 0x00 ||zastav vykonavani programu
                  next_state <= fsm_null;
                when others => -- jina hodnota
                  pc_inc <= '1';
                  next_state <= fsm_fetch;
              end case;

      
      when fsm_pointer_inc =>
                next_state <= fsm_start;
                ptr_inc <= '1';
                pc_inc <= '1';
      
      when fsm_pointer_dec =>
                next_state <= fsm_start;
                ptr_dec <= '1';
                pc_inc <= '1';
      
      when fsm_value_inc0 =>      
                next_state <= fsm_value_inc1;
                mx1_sel <= '1';

      when fsm_value_inc1 =>      
                next_state <= fsm_value_inc2;
                DATA_EN <= '1';
                mx1_sel <= '1';
                DATA_RDWR <= '0'; -- cteni
                

      when fsm_value_inc2 =>
                next_state <= fsm_value_inc3; 
                mx1_sel <= '1';
                mx2_sel <= "01";


      when fsm_value_inc3 =>
                next_state <= fsm_start; 
                DATA_RDWR <= '1'; -- zapis
                pc_inc <= '1';
                mx1_sel <= '1';
                DATA_EN <= '1'; 


      when fsm_value_dec0 =>      
                next_state <= fsm_value_dec1;
                mx1_sel <= '1'; -- ptr

      when fsm_value_dec1 =>      
                next_state <= fsm_value_dec2;
                DATA_EN <= '1';
                mx1_sel <= '1';
                DATA_RDWR <= '0'; -- cteni
                

      when fsm_value_dec2 =>
                next_state <= fsm_value_dec3; 
                mx1_sel <= '1'; -- ptr
                mx2_sel <= "10";


      when fsm_value_dec3 =>
                next_state <= fsm_start; 
                DATA_RDWR <= '1'; -- zapis
                pc_inc <= '1';
                mx1_sel <= '1'; -- ptr
                DATA_EN <= '1'; 
      
      
      when fsm_while_begin =>  
      
      
      when fsm_while_end =>       
      
      
      when fsm_do_while_begin => 
      
      
      when fsm_do_while_end =>    
      
      
      when fsm_print_value0 =>   
                if OUT_BUSY = '1' then
                  next_state <= fsm_print_value0;
                else
                  next_state <= fsm_print_value1;
                  mx1_sel <= '1'; -- ptr
                  DATA_EN <= '1';
                end if;


      when fsm_print_value1 =>
                next_state <= fsm_print_value2;
                DATA_EN <= '1';
                mx1_sel <= '1'; -- ptr
                DATA_RDWR <= '0'; -- cteni


      when fsm_print_value2 =>
                next_state <= fsm_print_value3;
                OUT_DATA <= DATA_RDATA;

      when fsm_print_value3 =>
                OUT_WE <= '1';
                pc_inc <= '1';
                next_state <= fsm_start;


      when fsm_get_value0 =>  
                IN_REQ <= '1';
                if IN_VLD = '0' then
                  next_state <= fsm_get_value0;
                else
                  next_state <= fsm_get_value1;
                  mx1_sel <= '1'; -- ptr
                end if;


      when fsm_get_value1 =>
                next_state <= fsm_get_value2;
                mx2_sel <= "00";
                mx1_sel <= '1'; -- ptr
      
      when fsm_get_value2 =>
                next_state <= fsm_start;
                mx2_sel <= "00";
                mx1_sel <= '1'; -- ptr
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
      
      
      
      when fsm_null => 
      when others => 
                next_state <= fsm_start;

  end case;


  end process;
  

  ------ CNT ------
  cnt_proc: process(CLK, RESET)
  begin
    if RESET = '1' then
      cnt_state <= (others => '0');
    elsif rising_edge(CLK) then
      if cnt_inc = '1' then
        cnt_state <= cnt_state + 1;
      elsif cnt_dec = '1' then
        cnt_state <= cnt_state - 1;
      end if;
      
    end if;
  end process;


  ---- PC ------
  pc_proc: process(CLK, RESET)
  begin
    if RESET = '1' then
      pc_state <= (others => '0');
    elsif rising_edge(CLK) then
      if pc_inc = '1' then
        pc_state <= pc_state + 1;
      elsif pc_dec = '1' then
        pc_state <= pc_state - 1;
      end if;
      
    end if;
  end process;



  ------ PTR ------
  ptr_proc: process(CLK, RESET)
  begin
    if RESET = '1' then
      ptr_state <= "1000000000000";
    elsif rising_edge(CLK) then
      if ptr_inc = '1' then
        ptr_state <= ptr_state + 1;
      elsif ptr_dec = '1' then
        ptr_state <= ptr_state - 1;
      end if;
      
    end if;
  end process;


  ------ MX1 ------
  mx1_proc: process(RESET, CLK, mx1_sel, pc_state, ptr_state)
  begin
    if RESET = '1' then
      DATA_ADDR <= (others => '0');
    elsif rising_edge(CLK) then
      if mx1_sel = '0' then
        DATA_ADDR <= pc_state;
      else
      DATA_ADDR <= ptr_state;
      end if;
    end if;
  end process;


  ------ MX2 ------
  mx2_proc: process(RESET, CLK, mx2_sel, DATA_RDATA, IN_DATA)
  begin
    if RESET = '1' then
      DATA_WDATA <= (others => '0');
    elsif rising_edge(CLK) then
      case mx2_sel is
        when "00" => DATA_WDATA <= IN_DATA;
        when "01" => DATA_WDATA <= DATA_RDATA + 1;
        when "10" => DATA_WDATA <= DATA_RDATA - 1;
        when others => DATA_WDATA <= (others => '0');
      end case;
    end if;
  end process;


end behavioral;






















