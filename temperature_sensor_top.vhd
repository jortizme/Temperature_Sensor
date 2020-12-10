library ieee;
use ieee.std_logic_1164.all;

entity temperature_sensor_top is
  port (
    --Clock ins, SYS_CLK = 50 MHz
    SYS_CLK :   in  std_logic;

    --Temperature sensor, I2C Interface (ADT7420)
    ADT7420_CT   :   in  std_logic;  --Not Use
    ADT7420_INT  :   in  std_logic;  --Not Use
    ADT7420_SCL  :   inout  std_logic;  
    ADT7420_SDA  :   inout  std_logic;  

    --LED outs
    USER_LED    :   out std_logic_vector(8 downto 1);

    GPIO_J3_39  :   out std_logic;  --UART TX
    GPIO_J3_40  :   in std_logic  --UART RX

  ) ;
end entity temperature_sensor_top;

architecture arch of temperature_sensor_top is

    signal locked, clk_uart_29Mhz_i, uart_rst_i : std_logic := '0';
    signal delay_8 : std_logic_vector(7 downto 0);

begin

    clk: entity work.pll_29p5M
        port map(
            inclk0  =>  SYS_CLK,            --50MHz clock input
            c0      =>  clk_uart_29Mhz_i,   --29.5Mhz clock input
            locked  =>  locked              --Lock condition, 1 = locked            
        );

    dealy_p: process(SYS_CLK)
    begin

        if(rising_edge(SYS_CLK)) then
            delay_8 <= delay_8(6 downto 0) & locked; --create active LOW reset 
        end if;
    end process;

    uart_rst_i  <= delay_8(7);

    uartTOi2c_pm: entity work.uartTOi2c
        port map(
            clk_uart_29Mhz_i    => clk_uart_29Mhz_i,
            uart_rst_i          => uart_rst_i,
            uart_leds_o         => USER_LED,
            clk_uart_monitor_o  => open,
            uart_dout_o         => GPIO_J3_39,
            uart_din_i          => GPIO_J3_40,
            i2c_scl             => ADT7420_SCL,
            i2c_dat             => ADT7420_SDA
        );


end architecture arch ; 