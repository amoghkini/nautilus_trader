#!/usr/bin/env python3
# -------------------------------------------------------------------------------------------------
# <copyright file="serialization.pyx" company="Invariance Pte">
#  Copyright (C) 2018-2019 Invariance Pte. All rights reserved.
#  The use of this source code is governed by the license as found in the LICENSE.md file.
#  http://www.invariance.com
# </copyright>
# -------------------------------------------------------------------------------------------------

# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False

import re
import msgpack

from decimal import Decimal
from uuid import UUID

from inv_trader.core.precondition cimport Precondition
from inv_trader.commands cimport *
from inv_trader.commands cimport CollateralInquiry
from inv_trader.model.enums import Broker, OrderSide, OrderType, TimeInForce, Currency, SecurityType
from inv_trader.enums.brokerage cimport Broker, broker_string
from inv_trader.enums.time_in_force cimport TimeInForce, time_in_force_string
from inv_trader.enums.order_side cimport OrderSide, order_side_string
from inv_trader.enums.order_type cimport OrderType, order_type_string
from inv_trader.enums.currency cimport Currency, currency_string
from inv_trader.enums.security_type cimport SecurityType, security_type_string
from inv_trader.model.identifiers cimport TraderId, StrategyId, OrderId, ExecutionId, AccountId, InstrumentId
from inv_trader.model.identifiers cimport GUID, Label, ExecutionTicket, AccountNumber
from inv_trader.model.objects cimport ValidString, Quantity, Symbol, Price, Money, Instrument
from inv_trader.model.order cimport Order, AtomicOrder
from inv_trader.model.events cimport Event, AccountEvent
from inv_trader.model.events cimport OrderInitialized, OrderSubmitted, OrderAccepted, OrderRejected, OrderWorking
from inv_trader.model.events cimport OrderExpired, OrderModified, OrderCancelled, OrderCancelReject
from inv_trader.model.events cimport OrderPartiallyFilled, OrderFilled
from inv_trader.common.serialization cimport (
parse_symbol,
convert_price_to_string,
convert_string_to_price,
convert_label_to_string,
convert_string_to_label,
convert_datetime_to_string,
convert_string_to_datetime)
from inv_trader.common.serialization cimport OrderSerializer, EventSerializer, CommandSerializer, InstrumentSerializer


cdef str UTF8 = 'utf-8'
cdef str NONE = 'NONE'
cdef str TYPE = 'Type'
cdef str ID = 'Id'
cdef str COMMAND = 'Command'
cdef str COMMAND_ID = 'CommandId'
cdef str COMMAND_TIMESTAMP = 'CommandTimestamp'
cdef str EVENT = 'Event'
cdef str EVENT_ID = 'EventId'
cdef str EVENT_TIMESTAMP = 'EventTimestamp'
cdef str COLLATERAL_INQUIRY = 'CollateralInquiry'
cdef str SUBMIT_ORDER = 'SubmitOrder'
cdef str SUBMIT_ATOMIC_ORDER = 'SubmitAtomicOrder'
cdef str CANCEL_ORDER = 'CancelOrder'
cdef str MODIFY_ORDER = 'ModifyOrder'
cdef str CANCEL_REASON = 'CancelReason'
cdef str ORDER = 'Order'
cdef str TIMESTAMP = 'Timestamp'
cdef str SYMBOL = 'Symbol'
cdef str ORDER_ID_BROKER = 'OrderIdBroker'
cdef str TRADER_ID = 'TraderId'
cdef str STRATEGY_ID = 'StrategyId'
cdef str POSITION_ID = 'PositionId'
cdef str ORDER_ID = 'OrderId'
cdef str INIT_ID = 'InitId'
cdef str LABEL = 'Label'
cdef str SUBMITTED_TIME = 'SubmittedTime'
cdef str ACCEPTED_TIME = 'AcceptedTime'
cdef str REJECTED_TIME = 'RejectedTime'
cdef str REJECTED_RESPONSE = 'RejectedResponse'
cdef str REJECTED_REASON = 'RejectedReason'
cdef str WORKING_TIME = 'WorkingTime'
cdef str CANCELLED_TIME = 'CancelledTime'
cdef str MODIFIED_TIME = 'ModifiedTime'
cdef str MODIFIED_PRICE = 'ModifiedPrice'
cdef str EXPIRE_TIME = 'ExpireTime'
cdef str EXPIRED_TIME = 'ExpiredTime'
cdef str EXECUTION_TIME = 'ExecutionTime'
cdef str EXECUTION_ID = 'ExecutionId'
cdef str EXECUTION_TICKET = 'ExecutionTicket'
cdef str ORDER_SIDE = 'OrderSide'
cdef str ORDER_TYPE = 'OrderType'
cdef str ENTRY = 'Entry'
cdef str STOP_LOSS = 'StopLoss'
cdef str TAKE_PROFIT = 'TakeProfit'
cdef str FILLED_QUANTITY = 'FilledQuantity'
cdef str LEAVES_QUANTITY = 'LeavesQuantity'
cdef str QUANTITY = 'Quantity'
cdef str AVERAGE_PRICE = 'AveragePrice'
cdef str PRICE = 'Price'
cdef str TIME_IN_FORCE = 'TimeInForce'
cdef str ACCOUNT_ID = 'AccountId'
cdef str ACCOUNT_NUMBER = 'AccountNumber'
cdef str BROKER = 'Broker'
cdef str CURRENCY = 'Currency'
cdef str CASH_BALANCE = 'CashBalance'
cdef str CASH_START_DAY = 'CashStartDay'
cdef str CASH_ACTIVITY_DAY = 'CashActivityDay'
cdef str MARGIN_USED_LIQUIDATION = 'MarginUsedLiquidation'
cdef str MARGIN_USED_MAINTENANCE = 'MarginUsedMaintenance'
cdef str MARGIN_RATIO = 'MarginRatio'
cdef str MARGIN_CALL_STATUS = 'MarginCallStatus'

cdef str BROKER_SYMBOL = 'BrokerSymbol'
cdef str QUOTE_CURRENCY = 'QuoteCurrency'
cdef str SECURITY_TYPE = 'SecurityType'
cdef str TICK_PRECISION = 'TickPrecision'
cdef str TICK_SIZE = 'TickSize'
cdef str ROUND_LOT_SIZE = 'RoundLotSize'
cdef str MIN_STOP_DISTANCE_ENTRY = 'MinStopDistanceEntry'
cdef str MIN_STOP_DISTANCE = 'MinStopDistance'
cdef str MIN_LIMIT_DISTANCE_ENTRY = 'MinLimitDistanceEntry'
cdef str MIN_LIMIT_DISTANCE = 'MinLimitDistance'
cdef str MIN_TRADE_SIZE = 'MinTradeSize'
cdef str MAX_TRADE_SIZE = 'MaxTradeSize'
cdef str ROLL_OVER_INTEREST_BUY = 'RollOverInterestBuy'
cdef str ROLL_OVER_INTEREST_SELL = 'RollOverInterestSell'


cdef class MsgPackOrderSerializer(OrderSerializer):
    """
    Provides a command serializer for the MessagePack specification.
    """

    cpdef bytes serialize(self, Order order):
        """
        Return the serialized MessagePack specification bytes from the given order.

        :param order: The order to serialize.
        :return: bytes.
        """
        if order is None:
            return msgpack.packb({})  # Null order

        return msgpack.packb({
            ID: order.id.value,
            SYMBOL: order.symbol.value,
            ORDER_SIDE: order_side_string(order.side),
            ORDER_TYPE: order_type_string(order.type),
            QUANTITY: order.quantity.value,
            PRICE: convert_price_to_string(order.price),
            LABEL: convert_label_to_string(order.label),
            TIME_IN_FORCE: time_in_force_string(order.time_in_force),
            EXPIRE_TIME: convert_datetime_to_string(order.expire_time),
            TIMESTAMP: convert_datetime_to_string(order.timestamp),
            INIT_ID: order.init_id.value})

    cpdef Order deserialize(self, bytes order_bytes):
        """
        Return the order deserialized from the given MessagePack specification bytes.

        :param order_bytes: The bytes to deserialize.
        :return: Order.
        :raises ValueError: If the event_bytes is empty.
        """
        Precondition.not_empty(order_bytes, 'order_bytes')

        cdef dict unpacked = msgpack.unpackb(order_bytes, raw=False)

        if len(unpacked) == 0:
            return None  # Null order

        return Order(order_id=OrderId(unpacked[ID]),
                     symbol=parse_symbol(unpacked[SYMBOL]),
                     order_side=OrderSide[unpacked[ORDER_SIDE]],
                     order_type=OrderType[unpacked[ORDER_TYPE]],
                     quantity=Quantity(unpacked[QUANTITY]),
                     timestamp=convert_string_to_datetime(unpacked[TIMESTAMP]),
                     price=convert_string_to_price(unpacked[PRICE]),
                     label=convert_string_to_label(unpacked[LABEL]),
                     time_in_force=TimeInForce[unpacked[TIME_IN_FORCE]],
                     expire_time=convert_string_to_datetime(unpacked[EXPIRE_TIME]))


cdef class MsgPackCommandSerializer(CommandSerializer):
    """
    Provides a command serializer for the MessagePack specification.
    """

    def __init__(self):
        """
        Initializes a new instance of the MsgPackCommandSerializer class.
        """
        self.order_serializer = MsgPackOrderSerializer()

    cpdef bytes serialize(self, Command command):
        """
        Return the serialized MessagePack specification bytes from the given command.

        :param: command: The command to serialize.
        :return: bytes.
        :raises: ValueError: If the command cannot be serialized.
        """
        cdef dict package = {
            TYPE: COMMAND,
            COMMAND_ID: command.id.value,
            COMMAND_TIMESTAMP: convert_datetime_to_string(command.timestamp)
        }

        if isinstance(command, CollateralInquiry):
            package[COMMAND] = COLLATERAL_INQUIRY
            return msgpack.packb(package)
        if isinstance(command, SubmitOrder):
            package[COMMAND] = SUBMIT_ORDER
            package[TRADER_ID] = command.trader_id.value
            package[STRATEGY_ID] = command.strategy_id.value
            package[POSITION_ID] = command.position_id.value
            package[ORDER] = self.order_serializer.serialize(command.order)
            return msgpack.packb(package)
        if isinstance(command, SubmitAtomicOrder):
            package[COMMAND] = SUBMIT_ATOMIC_ORDER
            package[TRADER_ID] = command.trader_id.value
            package[STRATEGY_ID] = command.strategy_id.value
            package[POSITION_ID] = command.position_id.value
            package[ENTRY] = self.order_serializer.serialize(command.atomic_order.entry)
            package[STOP_LOSS] = self.order_serializer.serialize(command.atomic_order.stop_loss)
            package[TAKE_PROFIT] = self.order_serializer.serialize(command.atomic_order.take_profit)
            return msgpack.packb(package)
        if isinstance(command, ModifyOrder):
            package[COMMAND] = MODIFY_ORDER
            package[TRADER_ID] = command.trader_id.value
            package[STRATEGY_ID] = command.strategy_id.value
            package[ORDER_ID] = command.order_id.value
            package[MODIFIED_PRICE] = str(command.modified_price)
            return msgpack.packb(package)
        if isinstance(command, CancelOrder):
            package[COMMAND] = CANCEL_ORDER
            package[TRADER_ID] = command.trader_id.value
            package[STRATEGY_ID] = command.strategy_id.value
            package[ORDER_ID] = command.order_id.value
            package[CANCEL_REASON] = command.cancel_reason.value
            return msgpack.packb(package)
        else:
            raise ValueError("Cannot serialize command (unrecognized command).")

    cpdef Command deserialize(self, bytes command_bytes):
        """
        Return the command deserialize from the given MessagePack specification command_bytes.

        :param command_bytes: The command to deserialize.
        :return: Command.
        :raises ValueError: If the command_bytes is empty.
        :raises ValueError: If the command cannot be deserialized.
        """
        Precondition.not_empty(command_bytes, 'command_bytes')

        cdef dict unpacked_raw = msgpack.unpackb(command_bytes)
        cdef dict unpacked = {}

        cdef str message_type = unpacked_raw[b'Type'].decode(UTF8)
        if message_type != COMMAND:
            raise ValueError("Cannot deserialize command (the message is not a type of command).")

        # Manually unpack and decode
        for k, v in unpacked_raw.items():
            if k not in (b'Order', b'Entry', b'StopLoss', b'TakeProfit'):
                if isinstance(v, bytes):
                    unpacked[k.decode(UTF8)] = v.decode(UTF8)
                else:
                    unpacked[k.decode(UTF8)] = v
            else:
                unpacked[k.decode(UTF8)] = v

        cdef str command = unpacked[COMMAND]
        cdef GUID command_id = GUID(UUID(unpacked[COMMAND_ID]))
        cdef datetime command_timestamp = convert_string_to_datetime(unpacked[COMMAND_TIMESTAMP])

        if command == COLLATERAL_INQUIRY:
            return CollateralInquiry(
                command_id,
                command_timestamp)
        if command == SUBMIT_ORDER:
            return SubmitOrder(
                TraderId(unpacked[TRADER_ID]),
                StrategyId(unpacked[STRATEGY_ID]),
                PositionId(unpacked[POSITION_ID]),
                self.order_serializer.deserialize(unpacked[ORDER]),
                command_id,
                command_timestamp)
        if command == SUBMIT_ATOMIC_ORDER:
            return SubmitAtomicOrder(
                TraderId(unpacked[TRADER_ID]),
                StrategyId(unpacked[STRATEGY_ID]),
                PositionId(unpacked[POSITION_ID]),
                AtomicOrder(self.order_serializer.deserialize(unpacked[ENTRY]),
                            self.order_serializer.deserialize(unpacked[STOP_LOSS]),
                            self.order_serializer.deserialize(unpacked[TAKE_PROFIT])),
                command_id,
                command_timestamp)
        if command == MODIFY_ORDER:
            return ModifyOrder(
                TraderId(unpacked[TRADER_ID]),
                StrategyId(unpacked[STRATEGY_ID]),
                OrderId(unpacked[ORDER_ID]),
                Price(unpacked[MODIFIED_PRICE]),
                command_id,
                command_timestamp)
        if command == CANCEL_ORDER:
            return CancelOrder(
                TraderId(unpacked[TRADER_ID]),
                StrategyId(unpacked[STRATEGY_ID]),
                OrderId(unpacked[ORDER_ID]),
                ValidString(unpacked[CANCEL_REASON]),
                command_id,
                command_timestamp)
        else:
            raise ValueError("Cannot deserialize command (unrecognized bytes pattern).")


cdef class MsgPackEventSerializer(EventSerializer):
    """
    Provides an event serializer for the MessagePack specification
    """

    cpdef bytes serialize(self, Event event):
        """
        Return the MessagePack specification bytes serialized from the given event.

        :param event: The event to serialize.
        :return: bytes.
        :raises: ValueError: If the event cannot be serialized.
        """
        cdef dict package = {
            TYPE: EVENT,
            EVENT: event.__class__.__name__,
            EVENT_ID: event.id.value,
            EVENT_TIMESTAMP: convert_datetime_to_string(event.timestamp)
        }

        if isinstance(event, AccountEvent):
            package[ACCOUNT_ID] = event.order_id.value
            package[BROKER] = broker_string(event.broker)
            package[ACCOUNT_NUMBER] = event.account_number.value
            package[CURRENCY] = currency_string(event.currency)
            package[CASH_BALANCE] = str(event.cash_balance)
            package[CASH_START_DAY] = str(event.cash_start_day)
            package[CASH_ACTIVITY_DAY] = str(event.cash_activity_day)
            package[MARGIN_USED_LIQUIDATION] = str(event.margin_used_liquidation)
            package[MARGIN_USED_MAINTENANCE] = str(event.margin_used_maintenance)
            package[MARGIN_RATIO] = str(event.margin_ratio)
            package[MARGIN_CALL_STATUS] = event.margin_call_status.value
            return msgpack.packb(package)
        if isinstance(event, OrderInitialized):
            package[ORDER_ID] = event.order_id.value
            package[SYMBOL] = event.symbol.value
            package[LABEL] = event.label.value
            package[ORDER_SIDE] = order_side_string(event.order_side)
            package[ORDER_TYPE] = order_type_string(event.order_type)
            package[QUANTITY] = event.quantity.value
            package[PRICE] = str(event.price)
            package[TIME_IN_FORCE] = time_in_force_string(event.time_in_force)
            package[EXPIRE_TIME] = convert_datetime_to_string(event.expire_time)
            return msgpack.packb(package)
        if isinstance(event, OrderSubmitted):
            package[ORDER_ID] =  event.order_id.value
            package[SUBMITTED_TIME] = convert_datetime_to_string(event.submitted_time)
            return msgpack.packb(package)
        if isinstance(event, OrderAccepted):
            package[ORDER_ID] =  event.order_id.value
            package[ACCEPTED_TIME] = convert_datetime_to_string(event.accepted_time)
            return msgpack.packb(package)
        if isinstance(event, OrderRejected):
            package[ORDER_ID] =  event.order_id.value
            package[REJECTED_TIME] = convert_datetime_to_string(event.rejected_time)
            package[REJECTED_REASON] =  str(event.rejected_reason)
            return msgpack.packb(package)
        if isinstance(event, OrderWorking):
            package[ORDER_ID] = event.order_id.value
            package[ORDER_ID_BROKER] = event.order_id_broker.value
            package[SYMBOL] = event.symbol.value
            package[LABEL] = event.label.value
            package[ORDER_SIDE] = order_side_string(event.order_side)
            package[ORDER_TYPE] = order_type_string(event.order_type)
            package[QUANTITY] = event.quantity.value
            package[PRICE] = str(event.price)
            package[TIME_IN_FORCE] = time_in_force_string(event.time_in_force)
            package[EXPIRE_TIME] = convert_datetime_to_string(event.expire_time)
            package[WORKING_TIME] = convert_datetime_to_string(event.working_time)
            return msgpack.packb(package)
        if isinstance(event, OrderCancelReject):
            package[ORDER_ID] = event.order_id.value
            package[REJECTED_TIME] = convert_datetime_to_string(event.cancel_reject_time)
            package[REJECTED_RESPONSE] = event.cancel_reject_response.value
            package[REJECTED_REASON] = event.cancel_reject_reason.value
            return msgpack.packb(package)
        if isinstance(event, OrderCancelled):
            package[ORDER_ID] = event.order_id.value
            package[CANCELLED_TIME] = convert_datetime_to_string(event.cancelled_time)
            return msgpack.packb(package)
        if isinstance(event, OrderModified):
            package[ORDER_ID] = event.order_id.value
            package[ORDER_ID_BROKER] = event.order_id_broker.value
            package[MODIFIED_TIME] = convert_datetime_to_string(event.modified_time)
            package[MODIFIED_PRICE] = str(event.modified_price)
            return msgpack.packb(package)
        if isinstance(event, OrderExpired):
            package[ORDER_ID] = event.order_id.value
            package[EXPIRED_TIME] = convert_datetime_to_string(event.expired_time)
            return msgpack.packb(package)
        if isinstance(event, OrderPartiallyFilled):
            package[ORDER_ID] = event.order_id.value
            package[EXECUTION_ID] = event.execution_id.value
            package[EXECUTION_TICKET] = event.execution_ticket.value
            package[SYMBOL] = event.symbol.value
            package[ORDER_SIDE] = order_side_string(event.order_side)
            package[FILLED_QUANTITY] = event.filled_quantity.value
            package[LEAVES_QUANTITY] = event.leaves_quantity.value
            package[AVERAGE_PRICE] = str(event.average_price)
            package[EXECUTION_TIME] = convert_datetime_to_string(event.execution_time)
            return msgpack.packb(package)
        if isinstance(event, OrderFilled):
            package[ORDER_ID] = event.order_id.value
            package[EXECUTION_ID] = event.execution_id.value
            package[EXECUTION_TICKET] = event.execution_ticket.value
            package[SYMBOL] = event.symbol.value
            package[ORDER_SIDE] = order_side_string(event.order_side)
            package[FILLED_QUANTITY] = event.filled_quantity.value
            package[AVERAGE_PRICE] = str(event.average_price)
            package[EXECUTION_TIME] = convert_datetime_to_string(event.execution_time)
            return msgpack.packb(package)
        else:
            raise ValueError("Cannot serialize event (unrecognized event.")

    cpdef Event deserialize(self, bytes event_bytes):
        """
        Return the event deserialized from the given MessagePack specification event_bytes.

        :param event_bytes: The bytes to deserialize.
        :return: Event.
        :raises ValueError: If the event_bytes is empty.
        :raises ValueError: If the event cannot be deserialized.
        """
        Precondition.not_empty(event_bytes, 'event_bytes')

        cdef dict unpacked = msgpack.unpackb(event_bytes, raw=False)

        cdef str message_type = unpacked[TYPE]
        if message_type != EVENT:
            raise ValueError("Cannot deserialize event (the message is not a type of event).")

        cdef str event_type = unpacked[EVENT]
        cdef GUID event_id = GUID(UUID(unpacked[EVENT_ID]))
        cdef datetime event_timestamp = convert_string_to_datetime(unpacked[EVENT_TIMESTAMP])

        if event_type == AccountEvent.__name__:
            return AccountEvent(
                AccountId(unpacked[ACCOUNT_ID]),
                Broker[unpacked[BROKER]],
                AccountNumber(unpacked[ACCOUNT_NUMBER]),
                Currency[unpacked[CURRENCY]],
                Money(unpacked[CASH_BALANCE]),
                Money(unpacked[CASH_START_DAY]),
                Money(unpacked[CASH_ACTIVITY_DAY]),
                Money(unpacked[MARGIN_USED_LIQUIDATION]),
                Money(unpacked[MARGIN_USED_MAINTENANCE]),
                Decimal(unpacked[MARGIN_RATIO]),
                ValidString('NONE'),
                event_id,
                event_timestamp)

        if event_type == OrderSubmitted.__name__:
            return OrderSubmitted(
                OrderId(unpacked[ORDER_ID]),
                convert_string_to_datetime(unpacked[SUBMITTED_TIME]),
                event_id,
                event_timestamp)
        if event_type == OrderAccepted.__name__:
            return OrderAccepted(
                OrderId(unpacked[ORDER_ID]),
                convert_string_to_datetime(unpacked[ACCEPTED_TIME]),
                event_id,
                event_timestamp)
        if event_type == OrderRejected.__name__:
            return OrderRejected(
                OrderId(unpacked[ORDER_ID]),
                convert_string_to_datetime(unpacked[REJECTED_TIME]),
                ValidString(unpacked[REJECTED_REASON]),
                event_id,
                event_timestamp)
        if event_type == OrderWorking.__name__:
            return OrderWorking(
                OrderId(unpacked[ORDER_ID]),
                OrderId(unpacked[ORDER_ID_BROKER]),
                parse_symbol(unpacked[SYMBOL]),
                Label(unpacked[LABEL]),
                OrderSide[unpacked[ORDER_SIDE]],
                OrderType[unpacked[ORDER_TYPE]],
                Quantity(unpacked[QUANTITY]),
                Price(unpacked[PRICE]),
                TimeInForce[unpacked[TIME_IN_FORCE]],
                convert_string_to_datetime(unpacked[WORKING_TIME]),
                event_id,
                event_timestamp,
                convert_string_to_datetime(unpacked[EXPIRE_TIME]))
        if event_type == OrderCancelled.__name__:
            return OrderCancelled(
                OrderId(unpacked[ORDER_ID]),
                convert_string_to_datetime(unpacked[CANCELLED_TIME]),
                event_id,
                event_timestamp)
        if event_type == OrderCancelReject.__name__:
            return OrderCancelReject(
                OrderId(unpacked[ORDER_ID]),
                convert_string_to_datetime(unpacked[REJECTED_TIME]),
                ValidString(unpacked[REJECTED_RESPONSE]),
                ValidString(unpacked[REJECTED_REASON]),
                event_id,
                event_timestamp)
        if event_type == OrderModified.__name__:
            return OrderModified(
                OrderId(unpacked[ORDER_ID]),
                OrderId(unpacked[ORDER_ID_BROKER]),
                Price(unpacked[MODIFIED_PRICE]),
                convert_string_to_datetime(unpacked[MODIFIED_TIME]),
                event_id,
                event_timestamp)
        if event_type == OrderExpired.__name__:
            return OrderExpired(
                OrderId(unpacked[ORDER_ID]),
                convert_string_to_datetime(unpacked[EXPIRED_TIME]),
                event_id,
                event_timestamp)
        if event_type == OrderPartiallyFilled.__name__:
            return OrderPartiallyFilled(
                OrderId(unpacked[ORDER_ID]),
                ExecutionId(unpacked[EXECUTION_ID]),
                ExecutionTicket(unpacked[EXECUTION_TICKET]),
                parse_symbol(unpacked[SYMBOL]),
                OrderSide[unpacked[ORDER_SIDE]],
                Quantity(unpacked[FILLED_QUANTITY]),
                Quantity(unpacked[LEAVES_QUANTITY]),
                Price(unpacked[AVERAGE_PRICE]),
                convert_string_to_datetime(unpacked[EXECUTION_TIME]),
                event_id,
                event_timestamp)
        if event_type == OrderFilled.__name__:
            return OrderFilled(
                OrderId(unpacked[ORDER_ID]),
                ExecutionId(unpacked[EXECUTION_ID]),
                ExecutionTicket(unpacked[EXECUTION_TICKET]),
                parse_symbol(unpacked[SYMBOL]),
                OrderSide[unpacked[ORDER_SIDE]],
                Quantity(unpacked[FILLED_QUANTITY]),
                Price(unpacked[AVERAGE_PRICE]),
                convert_string_to_datetime(unpacked[EXECUTION_TIME]),
                event_id,
                event_timestamp)
        else:
            raise ValueError("Cannot deserialize event (unrecognized event).")


cdef class MsgPackInstrumentSerializer(InstrumentSerializer):
    """
    Provides an instrument serializer for the MessagePack specification.
    """

    cpdef bytes serialize(self, Instrument instrument):
        """
        Return the MessagePack specification bytes serialized from the given instrument.

        :param instrument: The instrument to serialize.
        :return: bytes.
        """
        return msgpack.packb({
            ID: instrument.id.value,
            SYMBOL: instrument.symbol.value,
            BROKER_SYMBOL: instrument.broker_symbol,
            QUOTE_CURRENCY: currency_string(instrument.quote_currency),
            SECURITY_TYPE: security_type_string(instrument.security_type),
            TICK_PRECISION: instrument.tick_precision,
            TICK_SIZE: str(instrument.tick_size),
            ROUND_LOT_SIZE: instrument.round_lot_size.value,
            MIN_STOP_DISTANCE_ENTRY: instrument.min_stop_distance_entry,
            MIN_STOP_DISTANCE: instrument.min_stop_distance,
            MIN_LIMIT_DISTANCE_ENTRY: instrument.min_limit_distance_entry,
            MIN_LIMIT_DISTANCE: instrument.min_limit_distance,
            MIN_TRADE_SIZE: instrument.min_trade_size.value,
            MAX_TRADE_SIZE: instrument.max_trade_size.value,
            ROLL_OVER_INTEREST_BUY: str(instrument.rollover_interest_buy),
            ROLL_OVER_INTEREST_SELL: str(instrument.rollover_interest_sell),
            TIMESTAMP: convert_datetime_to_string(instrument.timestamp),
        })

    cpdef Instrument deserialize(self, bytes instrument_bytes):
        """
        Return the instrument deserialized from the given MessagePack specification bytes.

        :param instrument_bytes: The bytes to deserialize.
        :return: Instrument.
        """
        cdef dict unpacked = msgpack.unpackb(instrument_bytes, raw=False)

        return Instrument(
            instrument_id=InstrumentId(unpacked[ID]),
            symbol=parse_symbol(unpacked[SYMBOL]),
            broker_symbol=unpacked[BROKER_SYMBOL],
            quote_currency=Currency[(unpacked[QUOTE_CURRENCY])],
            security_type=SecurityType[(unpacked[SECURITY_TYPE])],
            tick_precision=unpacked[TICK_PRECISION],
            tick_size=Decimal(unpacked[TICK_SIZE]),
            round_lot_size=Quantity(unpacked[ROUND_LOT_SIZE]),
            min_stop_distance_entry=unpacked[MIN_STOP_DISTANCE_ENTRY],
            min_stop_distance=unpacked[MIN_STOP_DISTANCE],
            min_limit_distance_entry=unpacked[MIN_LIMIT_DISTANCE_ENTRY],
            min_limit_distance=unpacked[MIN_LIMIT_DISTANCE],
            min_trade_size=Quantity(unpacked[MIN_TRADE_SIZE]),
            max_trade_size=Quantity(unpacked[MAX_TRADE_SIZE]),
            rollover_interest_buy=Decimal(unpacked[ROLL_OVER_INTEREST_BUY]),
            rollover_interest_sell=Decimal(unpacked[ROLL_OVER_INTEREST_SELL]),
            timestamp=convert_string_to_datetime(unpacked[TIMESTAMP]))
