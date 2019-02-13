#!/usr/bin/env python3
# -------------------------------------------------------------------------------------------------
# <copyright file="backtest_example.py" company="Invariance Pte">
#  Copyright (C) 2018-2019 Invariance Pte. All rights reserved.
#  The use of this source code is governed by the license as found in the LICENSE.md file.
#  http://www.invariance.com
# </copyright>
# -------------------------------------------------------------------------------------------------

import pandas as pd
import logging

from datetime import datetime, timezone

from inv_trader.model.enums import Resolution
from inv_trader.backtest.engine import BacktestConfig, BacktestEngine
from test_kit.strategies import EMACross
from test_kit.data import TestDataProvider
from test_kit.stubs import TestStubs

if __name__ == "__main__":
    usdjpy = TestStubs.instrument_usdjpy()
    bid_data_1min = TestDataProvider.usdjpy_1min_bid()
    ask_data_1min = TestDataProvider.usdjpy_1min_ask()

    instruments = [TestStubs.instrument_usdjpy()]
    tick_data = {usdjpy.symbol: pd.DataFrame()}
    bid_data = {usdjpy.symbol: {Resolution.MINUTE: bid_data_1min}}
    ask_data = {usdjpy.symbol: {Resolution.MINUTE: ask_data_1min}}

    strategies = [EMACross(
        label='001',
        id_tag_trader='001',
        id_tag_strategy='001',
        instrument=usdjpy,
        bar_type=TestStubs.bartype_usdjpy_1min_bid(),
        position_size=100000,
        fast_ema=10,
        slow_ema=20,
        atr_period=20,
        sl_atr_multiple=2.0)]

    config = BacktestConfig(
        slippage_ticks=1,
        level_console=logging.INFO,
        log_to_file=False)
    engine = BacktestEngine(
        instruments=instruments,
        data_ticks=tick_data,
        data_bars_bid=bid_data,
        data_bars_ask=ask_data,
        strategies=strategies,
        config=config)

    start = datetime(2013, 1, 2, 0, 0, 0, 0, tzinfo=timezone.utc)
    stop = datetime(2013, 1, 3, 0, 0, 0, 0, tzinfo=timezone.utc)

    engine.run(start, stop)

    input("Press Enter to continue...")
