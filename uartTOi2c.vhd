library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartTOi2c is
  port (
    clk_uart_29MHz_i    : in std_logic;
    uart_rst_i          : in std_logic;
    uart_leds_o         : out std_logic_vector(7 downto 0);
    clk_uart_monitor_o  : out std_logic;

    -----------UART TX & RX----------------
    uart_dout_o         : out std_logic;
    uart_din_i          : in std_logic;

    -----------I2C interface--------------
    i2c_scl             : inout std_logic;  --serial clock
    i2c_dat             : inout std_logic  --seria data
  ) ;
end entity uartTOi2c;

architecture rtl of uartTOi2c is

    signal s_rst       : std_logic;    --main reset
    signal s_clk_uart   : std_logic;  --slow (29MHz) clock
    --uart control signals
    signal s_uart_br_clk            : std_logic; --unused clock monitor
    signal s_uart_rx_add            : std_logic_vector(15 downto 0);
    signal s_uart_rx_data           : std_logic_vector(31 downto 0);
    signal s_uart_rx_rdy            : std_logic;
    signal s_uart_rx_stb_read_data  : std_logic;
    signal s_update                 : std_logic;
    signal s_uart_tx_add            : std_logic_vector(15 downto 0);
    signal s_uart_tx_data           : std_logic_vector(31 downto 0);
    signal s_uart_tx_data_rdy       : std_logic;
    signal s_uart_tx_req            : std_logic;
    signal s_uart_tx_stb_acq        : std_logic;
    signal s_tx_complete            : std_logic;
    -- address decoder signals
    signal r_config_addr_uart       : std_logic_vector(1 downto 0);
    signal r_leds                   : std_logic_vector(7 downto 0); --0x0000
    signal reg01                    : std_logic_vector(31 downto 0);--00010
    signal reg02                    : std_logic_vector(31 downto 0);--00001
    ------------------------------------------------
    --signals for i2c Master block --
    ------------------------------------------------
    signal s_rst_n      : std_logic;
    signal i2c_busy     : std_logic;
    signal i2c_busy_dly : std_logic;
    signal i2c_busy_01  : std_logic; -- rising edge for i2c_busy
    signal i2cByte1     : std_logic;
    signal i2c_2bytes   : std_logic;
    signal data_wr      : std_logic_vector(7 downto 0);
    signal data_rd      : std_logic_vector(7 downto 0);
    -------------------------------------------------
    -- State Machine states--
    -------------------------------------------------
    type t_tx_reg_map is (IDLE, WAIT_A_BYTE, LATCH, TRANSMIT);
    signal s_tx_fsm     : t_tx_reg_map;

begin

    s_rst   <= not uart_rst_i;  --Change to active hight reset
    s_rst_n <= uart_rst_i;      --active low reset
    uart_leds_o <= not r_leds;  --Output LED with '1' mean on 
    s_clk_uart          <= clk_uart_29MHz_i;    --UART system clock 29.4912 MHz
    clk_uart_monitor_o  <= s_uart_br_clk;       
    i2c_busy_01 <= i2c_busy and not i2c_busy_dly;
    i2c_2bytes  <= reg01(30);   --This i2c command has 2 bytes  
    --Data write to the I2C Master depends on # of bytes operation
    data_wr <= reg01(7 downto 0) when i2cByte1 = '0' else reg01(15 downto 8);
    
    --UART simple register map : UART to BeMicro MAX10
    register_map : process(s_rst, s_clk_uart)
    begin
        if s_rst = '1' then         --reset all registers here
            s_uart_rx_stb_read_data <= '0';
            s_update                <= '0';
            r_leds                  <= (others => '0');
            r_config_addr_uart      <= "10";
            reg01                   <= (others => '0');
            i2c_busy_dly            <= '0';
            i2cByte1                <= '0';
        elsif rising_edge(s_clk_uart) then
            i2c_busy_dly <= i2c_busy;
            if s_uart_rx_rdy = '1' then
                case( s_uart_rx_add ) is
                
                    when x"0000" => r_leds  <= s_uart_rx_data(7 downto 0);
                    when x"0010" => reg01   <= s_uart_rx_data;
                    when x"8000" => s_update <= '1';    --register update self clearing  
                    when others => null;
                end case ;
                
                s_uart_rx_stb_read_data <= '1';
            else
                s_uart_rx_stb_read_data <= '0';
                s_update                <= '0'; --register update self clearing

                --Last byte send out to the i2c Master, then clean up data bits
                if(i2c_busy_01 = '1' and i2cByte1 = '0'  and i2c_2bytes = '0' ) then
                    reg01(29 downto 0)  <= (others => '0');
                end if;

                --After send the command to the I2C Master, then clean up command bits 
                if (i2c_busy_01 = '1' and (i2cByte1 = i2c_2bytes)) then     --11 or 00 condition
                reg01(31 downto 30) <= (others => '0');
                end if ;

                if (s_uart_rx_stb_read_data = '1') then
                    i2cByte1    <= '0';     --reset the condition after UART read request
                elsif (i2c_2bytes = '1' and i2c_busy_01 = '1') then
                    --Toggle every time i2c_busy change from low to high and two bytes operations
                    i2cByte1 <= not i2cByte1;
                end if ;
            end if ;
        end if ;
    end process;


end architecture rtl ; -