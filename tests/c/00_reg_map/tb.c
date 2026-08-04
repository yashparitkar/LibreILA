/*******************************************************************************
 * @file tb.c
 * @author Y.U.P. (yashparitkar)
 * @brief The baremetal driver's register map, against the map itself.
 *
 * The driver reaches the hardware only through HW_*_reg(), so stubbing those
 * out over an array (stub/fake_regs.c) runs the whole thing on the host. What
 * that buys is a check on *where* the driver decided to put each access, which
 * is the part that used to be decided at build time by a #define and is now
 * worked out at runtime from what the core reports.
 *
 * Register indices below are computed here from the map in the top level
 * README rather than taken from the driver, so a driver that derives them
 * wrong disagrees with this file instead of agreeing with itself. Same reason
 * tests/python/00_pkt_format works out its own offsets.
 *
 * The map, all indices from the AXI4Lite base, a = stride:
 *
 *   0  .. 7            output block, fixed size in every build
 *   8  .. 11           TRIG_POS, ARM_FT, TRIG_CFG, DISARM
 *   12 .. 12+a-1       TRIG_COND
 *   12+a .. 12+2a-1    TRIG_MASK
 *   12+2a ..           sample buffer, a registers per sample
 *
 * Copyright 2026 Yash Paritkar
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

#include <stdio.h>
#include <string.h>

#include "core_libre_ila.h"
#include "fake_regs.h"

/* ---- test harness ------------------------------------------------------- */

static unsigned g_checks;
static unsigned g_failures;
static const char * g_case;

#define CHECK(cond)                                                     \
    do {                                                                \
        g_checks++;                                                     \
        if (!(cond)) {                                                  \
            g_failures++;                                               \
            printf("  FAIL %s:%d [%s]  %s\n",                           \
                   __FILE__, __LINE__, g_case, #cond);                  \
        }                                                               \
    } while (0)

#define CHECK_EQ(got, want)                                             \
    do {                                                                \
        uint32_t g_ = (uint32_t)(got), w_ = (uint32_t)(want);           \
        g_checks++;                                                     \
        if (g_ != w_) {                                                 \
            g_failures++;                                               \
            printf("  FAIL %s:%d [%s]  %s: got 0x%08x, want 0x%08x\n",  \
                   __FILE__, __LINE__, g_case, #got,                    \
                   (unsigned)g_, (unsigned)w_);                         \
        }                                                               \
    } while (0)

/* ---- the map, worked out independently of the driver -------------------- */

#define OP_REGS   (8u)

static uint32_t lanes_of(uint32_t width)
{
    return (width + 31u) / 32u;
}

static uint32_t stride_of(uint32_t width)
{
    uint32_t stride = 1u;
    uint32_t lanes  = lanes_of(width);

    while (stride < lanes) { stride <<= 1u; }

    return (stride < 4u) ? 4u : stride;
}

static uint32_t ip_reg(uint32_t n)                { return OP_REGS + n; }
static uint32_t cond_reg(uint32_t n)              { return OP_REGS + 4u + n; }
static uint32_t mask_reg(uint32_t w, uint32_t n)  { return OP_REGS + 4u + stride_of(w) + n; }
static uint32_t buff_reg(uint32_t w, uint32_t samp, uint32_t lane)
{
    uint32_t stride = stride_of(w);
    return OP_REGS + 4u + 2u * stride + samp * stride + lane;
}

/* Output block, the four the driver reads while constructing plus the two
 * indices it reads on the way out. All at fixed addresses in every build,
 * which is the whole reason this ordering was chosen. */
#define REG_STATUS    (0u)
#define REG_MGCKEY    (1u)
#define REG_FREQ      (2u)
#define REG_WIDTH     (3u)
#define REG_DEPTH     (4u)
#define REG_UID       (5u)
#define REG_TRIG_IDX  (6u)
#define REG_FRST_IDX  (7u)

/* Staged non-zero so that a driver which never reads the register is caught,
 * rather than agreeing with the zero fake_regs_clear() left behind. */
#define STAGED_UID    (0x0badc0deu)

static void stage_core(uint32_t width, uint32_t depth, uint32_t freq)
{
    fake_regs_clear();

    fake_reg[REG_MGCKEY] = 0xb01dfaceu;
    fake_reg[REG_FREQ]   = freq;
    fake_reg[REG_WIDTH]  = width;
    fake_reg[REG_DEPTH]  = depth;
    fake_reg[REG_UID]    = STAGED_UID;
}

/* ---- the geometry init() derives --------------------------------------- */

static void test_geometry(void)
{
    libre_ila_instance_t ila;

    g_case = "geometry";

    stage_core(67u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);

    /* Read back rather than assumed, none of this came from a #define */
    CHECK_EQ(ila.probe_width,      67u);
    CHECK_EQ(ila.samp_buff_depth,  8u);
    CHECK_EQ(ila.samp_clk_freq_hz, 100000000u);

    /* Carried, not derived from. Nothing in the map moves with it, it is here
     * so that one binary can tell apart the cores it is driving. */
    CHECK_EQ(ila.uid, STAGED_UID);

    /* 67 bits need 3 lanes, and 3 rounds up to a stride of 4. The two are not
     * the same number and the map uses both. */
    CHECK_EQ(ila.n_lanes,      3u);
    CHECK_EQ(ila.stride_width, 4u);

    CHECK_EQ(ila.op_base,   0u);
    CHECK_EQ(ila.ip_base,   OP_REGS * 4u);
    CHECK_EQ(ila.mask_base, mask_reg(67u, 0u) * 4u);
    CHECK_EQ(ila.buff_base, buff_reg(67u, 0u, 0u) * 4u);
}

/* ---- writes land on the registers the map says ------------------------- */

static void test_control_writes(void)
{
    libre_ila_instance_t ila;
    uint32_t cond[4] = {0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u};
    uint32_t mask[4] = {0x0000000fu, 0u, 0u, 0u};
    uint32_t i;

    g_case = "control writes";

    stage_core(67u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);

    CHECK_EQ(LIBRE_ILA_set_trigger_position(&ila, 5u), CMD_STATUS_SUCCESS);
    CHECK_EQ(fake_reg[ip_reg(0u)], 5u);

    /* The trigger has to sit inside the window */
    CHECK_EQ(LIBRE_ILA_set_trigger_position(&ila, 8u), CMD_STATUS_BAD_PARAM);
    CHECK_EQ(LIBRE_ILA_set_trigger_position(&ila, 7u), CMD_STATUS_SUCCESS);

    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, cond, mask, 4u,
                                         LIBRE_ILA_TRIG_MODE_OR),
             CMD_STATUS_SUCCESS);

    /* cond is at a constant offset inside the input block, mask a whole
     * stride above it, which is the first address in the map that moves */
    for (i = 0u; i < 4u; i++)
    {
        CHECK_EQ(fake_reg[cond_reg(i)],      cond[i]);
        CHECK_EQ(fake_reg[mask_reg(67u, i)], mask[i]);
    }

    CHECK_EQ(fake_reg[ip_reg(2u)], (uint32_t)LIBRE_ILA_TRIG_MODE_OR);

    /* Configuring the trigger should not have reached DISARM or the output
     * block on the way past */
    CHECK_EQ(fake_reg[ip_reg(3u)], 0u);
    CHECK_EQ(fake_reg[REG_MGCKEY], 0xb01dfaceu);

    /* Arming is a write to input index 1, whatever value goes with it */
    CHECK_EQ(LIBRE_ILA_arm(&ila), CMD_STATUS_SUCCESS);
    CHECK(fake_reg[ip_reg(1u)] != 0u);

    /* And disarming index 3, the register that used to be the reserved one */
    fake_reg[REG_STATUS] = 0x1u;
    CHECK_EQ(LIBRE_ILA_disarm(&ila), CMD_STATUS_SUCCESS);
    CHECK(fake_reg[ip_reg(3u)] != 0u);
}

/* ---- the argument checks ------------------------------------------------ */

static void test_argument_checks(void)
{
    libre_ila_instance_t ila;
    uint32_t cond[4] = {0};
    uint32_t mask[4] = {0};
    uint32_t before;

    g_case = "argument checks";

    stage_core(67u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);

    /* A short vector would leave the top of the trigger holding whatever the
     * last configuration left there, a long one says the caller thinks the
     * core is a different shape than it is. Neither is guessed at. */
    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, cond, mask, 3u,
                                         LIBRE_ILA_TRIG_MODE_AND),
             CMD_STATUS_BAD_PARAM);
    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, cond, mask, 8u,
                                         LIBRE_ILA_TRIG_MODE_AND),
             CMD_STATUS_BAD_PARAM);

    /* and nothing was written on the way to the refusal */
    CHECK_EQ(fake_reg[cond_reg(0u)], 0u);
    CHECK_EQ(fake_reg[ip_reg(2u)],   0u);

    /* TRIG_CFG defines bits 2 downto 0 and nothing else */
    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, cond, mask, 4u,
                                         (libre_ila_trig_mode_t)0x8u),
             CMD_STATUS_BAD_PARAM);

    /* A level trigger has no direction, so FALLING without EDGE is a mistake
     * worth naming rather than ignoring */
    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, cond, mask, 4u,
                                         LIBRE_ILA_TRIG_FALLING),
             CMD_STATUS_BAD_PARAM);
    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, cond, mask, 4u,
                 (libre_ila_trig_mode_t)(LIBRE_ILA_TRIG_FALLING | LIBRE_ILA_TRIG_EDGE)),
             CMD_STATUS_SUCCESS);

    CHECK_EQ(LIBRE_ILA_configure_trigger(&ila, NULL, mask, 4u,
                                         LIBRE_ILA_TRIG_MODE_AND),
             CMD_STATUS_BAD_PARAM);

    /* A NULL instance is caught before anything is dereferenced */
    before = fake_reg[ip_reg(0u)];
    CHECK_EQ(LIBRE_ILA_init(NULL, 0u),                    CMD_STATUS_BAD_LIBRE_ILA);
    CHECK_EQ(LIBRE_ILA_set_trigger_position(NULL, 0u),    CMD_STATUS_BAD_LIBRE_ILA);
    CHECK_EQ(LIBRE_ILA_arm(NULL),                         CMD_STATUS_BAD_LIBRE_ILA);
    CHECK_EQ(LIBRE_ILA_force_trigger(NULL),               CMD_STATUS_BAD_LIBRE_ILA);
    CHECK_EQ(LIBRE_ILA_disarm(NULL),                      CMD_STATUS_BAD_LIBRE_ILA);
    CHECK_EQ(LIBRE_ILA_get_status(NULL),  (uint32_t)LIBRE_ILA_STATUS_BAD_LIBRE_ILA);
    CHECK_EQ(fake_reg[ip_reg(0u)], before);
}

/* ---- init refuses a core it cannot build a map from -------------------- */

static void test_init_rejections(void)
{
    libre_ila_instance_t ila;

    g_case = "init rejections";

    /* Nothing the core said is worth anything until the key checks out */
    stage_core(67u, 8u, 100000000u);
    fake_reg[REG_MGCKEY] = 0xdeadbeefu;
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_BAD_MAGIC_KEY);

    /* Both of these are asserted at elaboration in the HDL, so a core
     * reporting either is not one whatever the magic key says. They matter
     * because the map is now derived from them rather than checked against
     * them, so a nonsense value would otherwise surface much later as an
     * access at an address that means nothing. */
    stage_core(0u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_BAD_CONFIG);

    stage_core(67u, 1u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_BAD_CONFIG);

    stage_core(67u, 0u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_BAD_CONFIG);

    /* The uid is the one thing here that is never a reason to refuse. Every
     * value is legal and zero is what a core built without one reports, so
     * neither may be turned into a rejection: the magic key is what says the
     * core is a LibreILA, and it is unaffected by any of this. */
    stage_core(67u, 8u, 100000000u);
    fake_reg[REG_UID] = 0u;
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);
    CHECK_EQ(ila.uid, 0u);

    stage_core(67u, 8u, 100000000u);
    fake_reg[REG_UID] = 0xffffffffu;
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);
    CHECK_EQ(ila.uid, 0xffffffffu);
}

/* ---- status decode and the arm guards ---------------------------------- */

static void test_status(void)
{
    libre_ila_instance_t ila;

    g_case = "status";

    stage_core(67u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);

    /* Latest state first, and off the CDCed ARMED/TRIGD/DONE bits rather than
     * the STATE field, which is not synchronised into this clock domain */
    fake_reg[REG_STATUS] = 0u;
    CHECK_EQ(LIBRE_ILA_get_status(&ila), (uint32_t)LIBRE_ILA_STATUS_IDLE);

    fake_reg[REG_STATUS] = 0x1u;
    CHECK_EQ(LIBRE_ILA_get_status(&ila), (uint32_t)LIBRE_ILA_STATUS_ARMED);

    fake_reg[REG_STATUS] = 0x3u;
    CHECK_EQ(LIBRE_ILA_get_status(&ila), (uint32_t)LIBRE_ILA_STATUS_TRIGGERED);

    fake_reg[REG_STATUS] = 0x7u;
    CHECK_EQ(LIBRE_ILA_get_status(&ila), (uint32_t)LIBRE_ILA_STATUS_DONE);

    /* Arm and force trigger are the same register, so each has to refuse the
     * state where it would do the other one's job */
    fake_reg[REG_STATUS] = 0x1u;
    CHECK_EQ(LIBRE_ILA_arm(&ila),           CMD_STATUS_ERROR);
    CHECK_EQ(LIBRE_ILA_force_trigger(&ila), CMD_STATUS_SUCCESS);

    fake_reg[REG_STATUS] = 0x0u;
    CHECK_EQ(LIBRE_ILA_force_trigger(&ila), CMD_STATUS_ERROR);
    CHECK_EQ(LIBRE_ILA_arm(&ila),           CMD_STATUS_SUCCESS);

    /* Disarm takes the two states that have a capture running, either side of
     * the trigger, and refuses idle and done where the hardware ignores it */
    fake_reg[REG_STATUS] = 0x1u;
    CHECK_EQ(LIBRE_ILA_disarm(&ila), CMD_STATUS_SUCCESS);

    fake_reg[REG_STATUS] = 0x3u;
    CHECK_EQ(LIBRE_ILA_disarm(&ila), CMD_STATUS_SUCCESS);

    fake_reg[REG_STATUS] = 0x0u;
    CHECK_EQ(LIBRE_ILA_disarm(&ila), CMD_STATUS_ERROR);

    fake_reg[REG_STATUS] = 0x7u;
    CHECK_EQ(LIBRE_ILA_disarm(&ila), CMD_STATUS_ERROR);

    fake_reg[REG_STATUS] = 0x4u;
    CHECK_EQ(LIBRE_ILA_wait_done(&ila, 10u), CMD_STATUS_SUCCESS);

    fake_reg[REG_STATUS] = 0x0u;
    CHECK_EQ(LIBRE_ILA_wait_done(&ila, 1u), CMD_STATUS_TIMEOUT);
}

/* ---- the readout ------------------------------------------------------- */

static void test_readout(void)
{
    libre_ila_instance_t ila;
    uint32_t samples[8u * 3u];
    uint32_t trig_pos;
    uint32_t frst_idx, read_trig_idx;
    uint32_t samp, lane;

    g_case = "readout";

    stage_core(67u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);

    /* A recognisable value per lane per slot, plus padding in the fourth
     * register of every stride that must not come out */
    for (samp = 0u; samp < 8u; samp++)
    {
        for (lane = 0u; lane < 3u; lane++)
        {
            fake_reg[buff_reg(67u, samp, lane)] = 0x1000u * samp + lane;
        }
        fake_reg[buff_reg(67u, samp, 3u)] = 0xbadbad00u;
    }

    fake_reg[REG_FRST_IDX] = 5u;  /* oldest sample sits in slot 5 */
    fake_reg[REG_TRIG_IDX] = 7u;  /* the trigger fired in slot 7  */

    CHECK_EQ(LIBRE_ILA_read_idx(&ila, &frst_idx, &read_trig_idx), CMD_STATUS_SUCCESS);
    CHECK_EQ(frst_idx,      5u);
    CHECK_EQ(read_trig_idx, 7u);

    CHECK_EQ(LIBRE_ILA_read_data(&ila, samples, 8u * 3u, &trig_pos),
             CMD_STATUS_SUCCESS);

    /* read_data unrolls the circular buffer from the oldest sample, so the
     * trigger comes back rebased onto that ordering rather than raw */
    CHECK_EQ(trig_pos, 2u);

    for (samp = 0u; samp < 8u; samp++)
    {
        uint32_t slot = (5u + samp) % 8u;

        for (lane = 0u; lane < 3u; lane++)
        {
            CHECK_EQ(LIBRE_ILA_SAMPLE_WORD(samples, samp, lane),
                     0x1000u * slot + lane);
        }
    }

    /* The stride padding is dropped on the way out, so nothing in the buffer
     * carries the marker written above */
    for (samp = 0u; samp < (8u * 3u); samp++)
    {
        CHECK(samples[samp] != 0xbadbad00u);
    }

    /* Exact rather than "at least": a buffer sized for a wider probe than the
     * core has would pass a loose check, get filled at one row length and be
     * indexed at another by LIBRE_ILA_SAMPLE_WORD() */
    CHECK_EQ(LIBRE_ILA_read_data(&ila, samples, 8u * 4u, &trig_pos),
             CMD_STATUS_BAD_PARAM);
    CHECK_EQ(LIBRE_ILA_read_data(&ila, samples, 8u * 2u, &trig_pos),
             CMD_STATUS_BAD_PARAM);
    CHECK_EQ(LIBRE_ILA_read_data(&ila, NULL, 8u * 3u, &trig_pos),
             CMD_STATUS_BAD_PARAM);
}

/* ---- two cores of different widths, one binary -------------------------- */

static void test_second_instance(void)
{
    libre_ila_instance_t narrow;
    libre_ila_instance_t wide;
    uint32_t wide_buf[LIBRE_ILA_SAMPLE_WORDS(512u, 4u)];
    uint32_t trig_pos;
    uint32_t samp, lane;

    g_case = "second instance";

    /* This is the case the driver could not express while the offsets were
     * macros: the map came from one global width, so a second core of another
     * width had nowhere to put its geometry. Now each instance carries its own
     * and only the arrays have to be sized per width. */
    stage_core(512u, 4u, 50000000u);
    CHECK_EQ(LIBRE_ILA_init(&wide, 0u), CMD_STATUS_SUCCESS);

    CHECK_EQ(wide.n_lanes,      16u);
    CHECK_EQ(wide.stride_width, 16u);
    CHECK_EQ(wide.mask_base, mask_reg(512u, 0u) * 4u);
    CHECK_EQ(wide.buff_base, buff_reg(512u, 0u, 0u) * 4u);

    /* Both bases sit well above where the 67 bit build put them */
    CHECK(wide.mask_base > (mask_reg(67u, 0u) * 4u));
    CHECK(wide.buff_base > (buff_reg(67u, 0u, 0u) * 4u));

    for (samp = 0u; samp < 4u; samp++)
    {
        for (lane = 0u; lane < 16u; lane++)
        {
            fake_reg[buff_reg(512u, samp, lane)] = 0x100u * samp + lane;
        }
    }

    fake_reg[REG_FRST_IDX] = 1u;
    fake_reg[REG_TRIG_IDX] = 3u;

    CHECK_EQ(sizeof(wide_buf) / sizeof(wide_buf[0]), 64u);
    CHECK_EQ(LIBRE_ILA_read_data(&wide, wide_buf,
                                 sizeof(wide_buf) / sizeof(wide_buf[0]), &trig_pos),
             CMD_STATUS_SUCCESS);
    CHECK_EQ(trig_pos, 2u);

    /* The global CORE_LIBRE_ILA_N_LANES describes the other core, so this one
     * is indexed with the lane count out of its own instance */
    for (samp = 0u; samp < 4u; samp++)
    {
        uint32_t slot = (1u + samp) % 4u;

        for (lane = 0u; lane < 16u; lane++)
        {
            CHECK_EQ(LIBRE_ILA_SAMPLE_WORD_N(wide_buf, wide.n_lanes, samp, lane),
                     0x100u * slot + lane);
        }
    }

    /* And an instance built against the narrow core keeps its own geometry,
     * the two do not share anything but the code */
    stage_core(67u, 8u, 100000000u);
    CHECK_EQ(LIBRE_ILA_init(&narrow, 0u), CMD_STATUS_SUCCESS);
    CHECK_EQ(narrow.stride_width, 4u);
    CHECK_EQ(wide.stride_width,   16u);
    CHECK(narrow.buff_base != wide.buff_base);
}

/* ---- the sizing macros ------------------------------------------------- */

static void test_sizing_macros(void)
{
    g_case = "sizing macros";

    /* These only size arrays now, but they still have to agree with what the
     * driver derives from the core or the length checks reject every call */
    CHECK_EQ(LIBRE_ILA_LANES_FOR(1u),    1u);
    CHECK_EQ(LIBRE_ILA_LANES_FOR(32u),   1u);
    CHECK_EQ(LIBRE_ILA_LANES_FOR(33u),   2u);
    CHECK_EQ(LIBRE_ILA_LANES_FOR(67u),   3u);
    CHECK_EQ(LIBRE_ILA_LANES_FOR(512u), 16u);

    CHECK_EQ(LIBRE_ILA_STRIDE_FOR(1u),    4u);
    CHECK_EQ(LIBRE_ILA_STRIDE_FOR(67u),   4u);
    CHECK_EQ(LIBRE_ILA_STRIDE_FOR(128u),  4u);
    CHECK_EQ(LIBRE_ILA_STRIDE_FOR(129u),  8u);
    CHECK_EQ(LIBRE_ILA_STRIDE_FOR(512u), 16u);

    CHECK_EQ(LIBRE_ILA_TRIG_WORDS(67u),          4u);
    CHECK_EQ(LIBRE_ILA_SAMPLE_WORDS(67u, 2048u), 3u * 2048u);

    /* The stock defaults describe the stock AXI4S build */
    CHECK_EQ(CORE_LIBRE_ILA_N_LANES,      3u);
    CHECK_EQ(CORE_LIBRE_ILA_STRIDE_WIDTH, 4u);

    /* Every stride the driver can derive at runtime has to match the macro,
     * they are two spellings of the same rule and both are in use */
    {
        libre_ila_instance_t ila;
        uint32_t widths[] = {1u, 32u, 33u, 67u, 128u, 129u, 256u, 257u, 512u};
        uint32_t i;

        for (i = 0u; i < (sizeof(widths) / sizeof(widths[0])); i++)
        {
            stage_core(widths[i], 4u, 100000000u);
            CHECK_EQ(LIBRE_ILA_init(&ila, 0u), CMD_STATUS_SUCCESS);
            CHECK_EQ(ila.stride_width, stride_of(widths[i]));
            CHECK_EQ(ila.n_lanes,      lanes_of(widths[i]));
        }
    }
}

int main(void)
{
    printf("00_reg_map: the baremetal driver against the register map\n");

    test_geometry();
    test_control_writes();
    test_argument_checks();
    test_init_rejections();
    test_status();
    test_readout();
    test_second_instance();
    test_sizing_macros();

    if (g_failures != 0u)
    {
        printf("00_reg_map FAILURE: %u of %u checks failed\n", g_failures, g_checks);
        return 1;
    }

    printf("00_reg_map SUCCESS: %u checks passed\n", g_checks);
    return 0;
}
