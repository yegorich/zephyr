/*
 * Copyright (c) 2016 Cadence Design Systems, Inc.
 * Copyright (c) 2017 Intel Corporation
 * Copyright (c) 2020 Espressif Systems (Shanghai) Co., Ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file
 * @brief Linker command/script file
 *
 * Linker script for the Xtensa platform.
 */

#include <devicetree.h>
#include <autoconf.h>
#include <linker/sections.h>
#include <linker/linker-defs.h>
#include <linker/linker-tool.h>

#define RAMABLE_REGION dram0_0_seg
#define RAMABLE_REGION_1 dram0_1_seg
#define RODATA_REGION drom0_0_seg
#define IRAM_REGION iram0_0_seg
#define FLASH_CODE_REGION irom0_0_seg

#define ROMABLE_REGION ROM

#ifdef CONFIG_FLASH_SIZE
#define ROM_SIZE CONFIG_FLASH_SIZE
#else
#define ROM_SIZE 0x400000
#endif

#ifdef CONFIG_BOOTLOADER_ESP_IDF
#define IROM_SEG_ORG 0x400D0020
#define IROM_SEG_LEN 0x330000-0x20
#define IROM_SEG_ALIGN 0x4
#else
#define IROM_SEG_ORG 0x400D0000
#define IROM_SEG_LEN 0x330000
#define IROM_SEG_ALIGN 0x10000
#endif

MEMORY
{
  mcuboot_hdr (RX): org = 0x0, len = 0x20
  metadata (RX): org = 0x20, len = 0x20
  ROM (RX): org = 0x40, len = ROM_SIZE - 0x40
  iram0_0_seg(RX): org = 0x40080000, len = 0x20000
  irom0_0_seg(RX): org = IROM_SEG_ORG, len = IROM_SEG_LEN
  /*
   * Following is DRAM memory split with reserved address ranges in ESP32:
   *
   * 0x3FFA_E000 - 0x3FFB_0000 (Reserved: data memory for ROM functions)
   * 0x3FFB_0000 - 0x3FFE_0000 (RAM bank 1 for application usage)
   * 0x3FFE_0000 - 0x3FFE_0440 (Reserved: data memory for ROM PRO CPU)
   * 0x3FFE_3F20 - 0x3FFE_4350 (Reserved: data memory for ROM APP CPU)
   * 0x3FFE_4350 - 0x3F10_0000 (RAM bank 2 for application usage)
   *
   * FIXME:
   *  - Utilize available memory regions to full capacity
   */
  dram0_0_seg(RW): org = 0x3FFB0000 + CONFIG_ESP32_BT_RESERVE_DRAM, len = 0x2c200 - CONFIG_ESP32_BT_RESERVE_DRAM
  dram0_1_seg(RW): org = 0x3FFE5230, len = 0x1BCB0 - 0xEE0 /* skip data for APP CPU initialization usage */

  /* DROM is the first segment placed in generated binary.
   * MCUboot binary for ESP32 has image header of 0x20 bytes.
   * Additional load header of 0x20 bytes are appended to the image.
   * Hence, an offset of 0x40 is added to DROM segment origin.
   */
  drom0_0_seg(R): org = 0x3F400040, len = 0x400000 - 0x40
  rtc_iram_seg(RWX): org = 0x400C0000, len = 0x2000
  rtc_slow_seg(RW): org = 0x50000000, len = 0x1000
#if defined(CONFIG_ESP_SPIRAM)
  ext_ram_seg(RW): org = 0x3F800000, len = CONFIG_ESP_SPIRAM_SIZE
#endif
#ifdef CONFIG_GEN_ISR_TABLES
  IDT_LIST(RW): org = 0x3ebfe010, len = 0x2000
#endif
}

/*  Default entry point:  */
PROVIDE ( _ResetVector = 0x40000400 );
ENTRY(CONFIG_KERNEL_ENTRY)

_rom_store_table = 0;

PROVIDE(_memmap_vecbase_reset = 0x40000450);
PROVIDE(_memmap_reset_vector = 0x40000400);

SECTIONS
{
  /* Reserve space for MCUboot header in the binary */
  .mcuboot_header :
  {
    QUAD(0x0)
    QUAD(0x0)
    QUAD(0x0)
    QUAD(0x0)
  } > mcuboot_hdr
  .metadata :
  {
    /* Magic byte for load header */
    LONG(0xace637d3)

    /* Application entry point address */
    KEEP(*(.entry_addr))

    /* IRAM metadata:
     * - Destination address (VMA) for IRAM region
     * - Flash offset (LMA) for start of IRAM region
     * - Size of IRAM region
     */

    LONG(ADDR(".iram0.vectors"))
    LONG(LOADADDR(".iram0.vectors"))
    LONG(LOADADDR(_TEXT_SECTION_NAME) + SIZEOF(_TEXT_SECTION_NAME) - LOADADDR(".iram0.vectors"))

    /* DRAM metadata:
     * - Destination address (VMA) for DRAM region
     * - Flash offset (LMA) for start of DRAM region
     * - Size of DRAM region
     */

    LONG(ADDR(".dram0.data"))
    LONG(LOADADDR(".dram0.data"))
    LONG(LOADADDR(".dummy.dram.data") + SIZEOF(".dummy.dram.data") - LOADADDR(".dram0.data"))
  } > metadata

#include <linker/rel-sections.ld>
  _image_drom_start = LOADADDR(_RODATA_SECTION_NAME);
  _image_drom_size = LOADADDR(_RODATA_SECTION_NAME) + SIZEOF(_RODATA_SECTION_NAME) - _image_drom_start;
  _image_drom_vaddr = ADDR(_RODATA_SECTION_NAME);

  /* NOTE: .rodata section should be the first section in the linker script and no
   * other section should appear before .rodata section. This is the requirement
   * to align ROM section to 64K page offset.
   * Adding .rodata as first section helps to reduce size of generated binary by
   * few kBs.
   */
  SECTION_PROLOGUE(_RODATA_SECTION_NAME,,)
  {
    _rodata_start = ABSOLUTE(.);

#ifdef CONFIG_USERSPACE
    Z_LINK_ITERABLE_ALIGNED(z_object_assignment, 4);
#endif

#if defined(CONFIG_NET_SOCKETS)
    Z_LINK_ITERABLE_ALIGNED(net_socket_register, 4);
#endif

#if defined(CONFIG_NET_L2_PPP)
    Z_LINK_ITERABLE_ALIGNED(ppp_protocol_handler, 4);
#endif

    Z_LINK_ITERABLE_ALIGNED(bt_l2cap_fixed_chan, 4);

#if defined(CONFIG_BT_BREDR)
    Z_LINK_ITERABLE_ALIGNED(bt_l2cap_br_fixed_chan, 4);
#endif

#if defined(CONFIG_BT_CONN)
    Z_LINK_ITERABLE_ALIGNED(bt_conn_cb, 4)
#endif

    Z_LINK_ITERABLE_ALIGNED(bt_gatt_service_static, 4);

#if defined(CONFIG_BT_MESH)
    Z_LINK_ITERABLE_ALIGNED(bt_mesh_subnet_cb, 4);
    Z_LINK_ITERABLE_ALIGNED(bt_mesh_app_key_cb, 4);
    Z_LINK_ITERABLE_ALIGNED(bt_mesh_hb_cb, 4);
#endif

#if defined(CONFIG_BT_MESH_FRIEND)
    Z_LINK_ITERABLE_ALIGNED(bt_mesh_friend_cb, 4);
#endif

#if defined(CONFIG_BT_MESH_LOW_POWER)
    Z_LINK_ITERABLE_ALIGNED(bt_mesh_lpn_cb, 4);
#endif

#if defined(CONFIG_BT_MESH_PROXY)
    Z_LINK_ITERABLE_ALIGNED(bt_mesh_proxy_cb, 4);
#endif

#if defined(CONFIG_EC_HOST_CMD)
    Z_LINK_ITERABLE_ALIGNED(ec_host_cmd_handler, 4);
#endif

#if defined(CONFIG_SETTINGS)
    Z_LINK_ITERABLE_ALIGNED(settings_handler_static, 4);
#endif

    Z_LINK_ITERABLE_ALIGNED(k_p4wq_initparam, 4);

    Z_LINK_ITERABLE_ALIGNED(shell, 4);

    Z_LINK_ITERABLE_ALIGNED(tracing_backend, 4)

    __esp_shell_root_cmds_start = .;
    KEEP(*(SORT(.shell_root_cmd_*)));
    __esp_shell_root_cmds_end = .;

    . = ALIGN(4);
    #include <snippets-rodata.ld>

    . = ALIGN(4);
    *(EXCLUDE_FILE (*libarch__xtensa__core.a:* *libkernel.a:fatal.* *libkernel.a:init.* *libzephyr.a:cbprintf_complete* *libzephyr.a:log_core.* *libzephyr.a:log_backend_uart.* *libzephyr.a:log_output.* *libzephyr.a:loader.* *libdrivers__flash.a:flash_esp32.* *libdrivers__serial.a:uart_esp32.*) .rodata)
    *(EXCLUDE_FILE (*libarch__xtensa__core.a:* *libkernel.a:fatal.* *libkernel.a:init.* *libzephyr.a:cbprintf_complete* *libzephyr.a:log_core.* *libzephyr.a:log_backend_uart.* *libzephyr.a:log_output.* *libzephyr.a:loader.* *libdrivers__flash.a:flash_esp32.* *libdrivers__serial.a:uart_esp32.*) .rodata.*)

    *(.gnu.linkonce.r.*)
    *(.rodata1)
    __XT_EXCEPTION_TABLE__ = ABSOLUTE(.);
    KEEP (*(.xt_except_table))
    KEEP (*(.gcc_except_table .gcc_except_table.*))
    *(.gnu.linkonce.e.*)
    *(.gnu.version_r)
    KEEP (*(.eh_frame))
    /*  C++ constructor and destructor tables, properly ordered:  */
    KEEP (*crtbegin.o(.ctors))
    KEEP (*(EXCLUDE_FILE (*crtend.o) .ctors))
    KEEP (*(SORT(.ctors.*)))
    KEEP (*(.ctors))
    KEEP (*crtbegin.o(.dtors))
    KEEP (*(EXCLUDE_FILE (*crtend.o) .dtors))
    KEEP (*(SORT(.dtors.*)))
    KEEP (*(.dtors))
    /*  C++ exception handlers table:  */
    __XT_EXCEPTION_DESCS__ = ABSOLUTE(.);
    *(.xt_except_desc)
    *(.gnu.linkonce.h.*)
    __XT_EXCEPTION_DESCS_END__ = ABSOLUTE(.);
    *(.xt_except_desc_end)
    *(.dynamic)
    *(.gnu.version_d)
    . = ALIGN(4);               /* this table MUST be 4-byte aligned */
    _rodata_end = ABSOLUTE(.);
  } GROUP_DATA_LINK_IN(RODATA_REGION, ROMABLE_REGION)

  _image_dram_start = LOADADDR(".dram0.data");
  _image_dram_size = LOADADDR(".dummy.dram.data") + SIZEOF(".dummy.dram.data") - _image_dram_start;
  _image_dram_vaddr = ADDR(".dram0.data");

  #include <snippets-sections.ld>

  .dram0.data :
  {
    _data_start = ABSOLUTE(.);

    _btdm_data_start = ABSOLUTE(.);
    *libbtdm_app.a:(.data .data.*)
    . = ALIGN (4);
    _btdm_data_end = ABSOLUTE(.);

    *(.data)
    *(.data.*)
    *(.gnu.linkonce.d.*)
    *(.data1)
    *(.sdata)
    *(.sdata.*)
    *(.gnu.linkonce.s.*)
    *(.sdata2)
    *(.sdata2.*)
    *(.gnu.linkonce.s2.*)
    /* rodata for panic handler(libarch__xtensa__core.a) and all
     * dependent functions should be placed in DRAM to avoid issue
     * when flash cache is disabled */
    *libarch__xtensa__core.a:(.rodata .rodata.*)
    *libkernel.a:fatal.*(.rodata .rodata.*)
    *libkernel.a:init.*(.rodata .rodata.*)
    *libzephyr.a:cbprintf_complete*(.rodata .rodata.*)
    *libzephyr.a:log_core.*(.rodata .rodata.*)
    *libzephyr.a:log_backend_uart.*(.rodata .rodata.*)
    *libzephyr.a:log_output.*(.rodata .rodata.*)
    *libzephyr.a:loader.*(.rodata .rodata.*)
    *libdrivers__flash.a:flash_esp32.*(.rodata  .rodata.*)
    *libdrivers__serial.a:uart_esp32.*(.rodata .rodata.*)

    KEEP(*(.jcr))
    *(.dram1 .dram1.*)
    . = ALIGN(4);
    _dram_data_end = ABSOLUTE(.);
  } GROUP_DATA_LINK_IN(RAMABLE_REGION, ROMABLE_REGION)

  #pragma push_macro("GROUP_ROM_LINK_IN")
  #pragma push_macro("ITERABLE_SECTION_ROM")
  #undef GROUP_ROM_LINK_IN
  #undef ITERABLE_SECTION_ROM
  #define GROUP_ROM_LINK_IN GROUP_DATA_LINK_IN
  #define ITERABLE_SECTION_ROM(x,y)
  #include <linker/common-rom.ld>
  #pragma pop_macro("GROUP_ROM_LINK_IN")
  #pragma pop_macro("ITERABLE_SECTION_ROM")

  #include <snippets-data-sections.ld>
  #include <linker/common-ram.ld>
  #include <snippets-ram-sections.ld>

  __shell_root_cmds_start = __esp_shell_root_cmds_start;
  __shell_root_cmds_end = __esp_shell_root_cmds_end;

  .dummy.dram.data :
  {
    . = ALIGN(4);
    #include <snippets-rwdata.ld>
    . = ALIGN(4);
    _data_end = ABSOLUTE(.);
  } GROUP_DATA_LINK_IN(RAMABLE_REGION, ROMABLE_REGION)

  _image_iram_start = LOADADDR(".iram0.vectors");
  _image_iram_size = LOADADDR(_TEXT_SECTION_NAME) + SIZEOF(_TEXT_SECTION_NAME) - _image_iram_start;
  _image_iram_vaddr = ADDR(".iram0.vectors");

  /* Send .iram0 code to iram */
  .iram0.vectors : ALIGN(4)
  {
    /* Vectors go to IRAM */
    _init_start = ABSOLUTE(.);
    /* Vectors according to builds/RF-2015.2-win32/esp108_v1_2_s5_512int_2/config.html */
    . = 0x0;
    KEEP(*(.WindowVectors.text));
    . = 0x180;
    KEEP(*(.Level2InterruptVector.text));
    . = 0x1c0;
    KEEP(*(.Level3InterruptVector.text));
    . = 0x200;
    KEEP(*(.Level4InterruptVector.text));
    . = 0x240;
    KEEP(*(.Level5InterruptVector.text));
    . = 0x280;
    KEEP(*(.DebugExceptionVector.text));
    . = 0x2c0;
    KEEP(*(.NMIExceptionVector.text));
    . = 0x300;
    KEEP(*(.KernelExceptionVector.text));
    . = 0x340;
    KEEP(*(.UserExceptionVector.text));
    . = 0x3C0;
    KEEP(*(.DoubleExceptionVector.text));
    . = 0x400;
    *(.*Vector.literal)

    *(.UserEnter.literal);
    *(.UserEnter.text);
    . = ALIGN (16);
    *(.entry.text)
    *(.init.literal)
    *(.init)
    _init_end = ABSOLUTE(.);

    /* This goes here, not at top of linker script, so addr2line finds it last,
       and uses it in preference to the first symbol in IRAM */
    _iram_start = ABSOLUTE(0);
  } GROUP_DATA_LINK_IN(IRAM_REGION, ROMABLE_REGION)

  SECTION_PROLOGUE(_TEXT_SECTION_NAME, , ALIGN(4))
  {
    /* Code marked as running out of IRAM */
    _iram_text_start = ABSOLUTE(.);
    *(.iram1 .iram1.*)
    *(.iram0.literal .iram.literal .iram.text.literal .iram0.text .iram.text)
    *libesp32.a:panic.*(.literal .text .literal.* .text.*)
    *librtc.a:(.literal .text .literal.* .text.*)
    *libsubsys__net__l2__ethernet.a:(.literal .text .literal.* .text.*)
    *libsubsys__net__lib__config.a:(.literal .text .literal.* .text.*)
    *libsubsys__net__ip.a:(.literal .text .literal.* .text.*)
    *libsubsys__net.a:(.literal .text .literal.* .text.*)
    *libarch__xtensa__core.a:(.literal .text .literal.* .text.*)
    *libkernel.a:(.literal .text .literal.* .text.*)
    *libsoc.a:rtc_*.*(.literal .text .literal.* .text.*)
    *libsoc.a:cpu_util.*(.literal .text .literal.* .text.*)
    *libgcc.a:lib2funcs.*(.literal .text .literal.* .text.*)
    *libdrivers__flash.a:flash_esp32.*(.literal .text .literal.* .text.*)
    *libzephyr.a:windowspill_asm.*(.literal .text .literal.* .text.*)
    *libzephyr.a:log_noos.*(.literal .text .literal.* .text.*)
    *libdrivers__timer.a:xtensa_sys_timer.*(.literal .text .literal.* .text.*)
    *libzephyr.a:log_core.*(.literal .text .literal.* .text.*)
    *libzephyr.a:cbprintf_complete.*(.literal .text .literal.* .text.*)
    *libzephyr.a:printk.*(.literal.printk .literal.vprintk .literal.char_out .text.printk .text.vprintk .text.char_out)
    *libzephyr.a:log_msg.*(.literal .text .literal.* .text.*)
    *libzephyr.a:log_list.*(.literal .text .literal.* .text.*)
    *libdrivers__console.a:uart_console.*(.literal.console_out .text.console_out)
    *libzephyr.a:log_output.*(.literal .text .literal.* .text.*)
    *libzephyr.a:log_backend_uart.*(.literal .text .literal.* .text.*)
    *libzephyr.a:loader.*(.literal .text .literal.* .text.*)
    *liblib__libc__minimal.a:string.*(.literal .text .literal.* .text.*)
    *libphy.a:( .phyiram .phyiram.*)
    *libgcov.a:(.literal .text .literal.* .text.*)

#if defined(CONFIG_ESP32_WIFI_IRAM_OPT)
    *libnet80211.a:( .wifi0iram  .wifi0iram.* .wifislpiram .wifislpiram.*)
    *libpp.a:( .wifi0iram  .wifi0iram.* .wifislpiram .wifislpiram.*)
#endif

#if defined(CONFIG_ESP32_WIFI_RX_IRAM_OPT)
    *libnet80211.a:( .wifirxiram  .wifirxiram.* .wifislprxiram .wifislprxiram.*)
    *libpp.a:( .wifirxiram  .wifirxiram.* .wifislprxiram .wifislprxiram.*)
#endif

    _iram_text_end = ABSOLUTE(.);
    . = ALIGN(4);
    _iram_end = ABSOLUTE(.);
  } GROUP_DATA_LINK_IN(IRAM_REGION, ROMABLE_REGION)

  /* RTC fast memory holds RTC wake stub code,
     including from any source file named rtc_wake_stub*.c
  */
  .rtc.text :
  {
    . = ALIGN(4);
    *(.rtc.literal .rtc.text)
    *rtc_wake_stub*.o(.literal .text .literal.* .text.*)
  } GROUP_DATA_LINK_IN(rtc_iram_seg, ROMABLE_REGION)

  /* RTC slow memory holds RTC wake stub
     data/rodata, including from any source file
     named rtc_wake_stub*.c
  */
  .rtc.data :
  {
    _rtc_data_start = ABSOLUTE(.);
    *(.rtc.data)
    *(.rtc.rodata)
    *rtc_wake_stub*.o(.data .rodata .data.* .rodata.* .bss .bss.*)
    _rtc_data_end = ABSOLUTE(.);
  } GROUP_DATA_LINK_IN(rtc_slow_seg, ROMABLE_REGION)

  /* RTC bss, from any source file named rtc_wake_stub*.c */
  .rtc.bss (NOLOAD) :
  {
    _rtc_bss_start = ABSOLUTE(.);
    *rtc_wake_stub*.o(.bss .bss.*)
    *rtc_wake_stub*.o(COMMON)
    _rtc_bss_end = ABSOLUTE(.);
  } GROUP_LINK_IN(rtc_slow_seg)

  /* Shared RAM */
  SECTION_DATA_PROLOGUE(_BSS_SECTION_NAME,(NOLOAD),)
  {
    . = ALIGN (8);
    _bss_start = ABSOLUTE(.);

    _btdm_bss_start = ABSOLUTE(.);
    *libbtdm_app.a:(.bss .bss.* COMMON)
    . = ALIGN (4);
    _btdm_bss_end = ABSOLUTE(.);

    /* Buffer for system heap should be placed in dram0_0_seg */
    *libkernel.a:mempool.*(.noinit.kheap_buf__system_heap .noinit.*.kheap_buf__system_heap)

    *(.dynsbss)
    *(.sbss)
    *(.sbss.*)
    *(.gnu.linkonce.sb.*)
    *(.scommon)
    *(.sbss2)
    *(.sbss2.*)
    *(.gnu.linkonce.sb2.*)
    *(.dynbss)
    *(.bss)
    *(.bss.*)
    *(.share.mem)
    *(.gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN (8);
    _bss_end = ABSOLUTE(.);
  } GROUP_LINK_IN(RAMABLE_REGION)

  ASSERT(((_bss_end - ORIGIN(dram0_0_seg)) <= LENGTH(dram0_0_seg)),
          "DRAM segment data does not fit.")

  SECTION_DATA_PROLOGUE(_NOINIT_SECTION_NAME, (NOLOAD),)
  {
    . = ALIGN (8);
    *(.noinit)
    *(.noinit.*)
    . = ALIGN (8);
  } GROUP_LINK_IN(RAMABLE_REGION_1)

#if defined(CONFIG_ESP_SPIRAM)
  .ext_ram.bss (NOLOAD):
  {
    _ext_ram_data_start = ABSOLUTE(.);
    *(.ext_ram.bss*)
    _ext_ram_data_end = ABSOLUTE(.) + CONFIG_ESP_SPIRAM_SIZE;
  } > ext_ram_seg
#endif

  _image_irom_start = LOADADDR(".flash.text");
  _image_irom_size = LOADADDR(".flash.text") + SIZEOF(".flash.text") - _image_irom_start;
  _image_irom_vaddr = ADDR(".flash.text");

  .flash.text : ALIGN(IROM_SEG_ALIGN)
  {
    _stext = .;
    _text_start = ABSOLUTE(.);

#if !defined(CONFIG_ESP32_WIFI_IRAM_OPT)
    *libnet80211.a:( .wifi0iram  .wifi0iram.* .wifislpiram .wifislpiram.*)
    *libpp.a:( .wifi0iram  .wifi0iram.* .wifislpiram .wifislpiram.*)
#endif

#if !defined(CONFIG_ESP32_WIFI_RX_IRAM_OPT)
    *libnet80211.a:( .wifirxiram  .wifirxiram.* .wifislprxiram .wifislprxiram.*)
    *libpp.a:( .wifirxiram  .wifirxiram.* .wifislprxiram .wifislprxiram.*)
#endif

    *(.literal .text .literal.* .text.*)
    . = ALIGN(4);
    _text_end = ABSOLUTE(.);
    _etext = .;

    /* Similar to _iram_start, this symbol goes here so it is
       resolved by addr2line in preference to the first symbol in
       the flash.text segment.
    */
    _flash_cache_start = ABSOLUTE(0);
  } GROUP_DATA_LINK_IN(FLASH_CODE_REGION, ROMABLE_REGION)

#ifdef CONFIG_GEN_ISR_TABLES
#include <linker/intlist.ld>
#endif

#include <linker/debug-sections.ld>

  SECTION_PROLOGUE(.xtensa.info, 0,)
  {
    *(.xtensa.info)
  }

}

ASSERT(((_iram_end - ORIGIN(iram0_0_seg)) <= LENGTH(iram0_0_seg)),
          "IRAM0 segment data does not fit.")
