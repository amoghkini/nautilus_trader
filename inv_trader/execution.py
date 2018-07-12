#!/usr/bin/env python3
# -------------------------------------------------------------------------------------------------
# <copyright file="execution.py" company="Invariance Pte">
#  Copyright (C) 2018 Invariance Pte. All rights reserved.
#  The use of this source code is governed by the license as found in the LICENSE.md file.
#  http://www.invariance.com
# </copyright>
# -------------------------------------------------------------------------------------------------

import abc
import time
import redis
import uuid
import iso8601

from datetime import datetime
from decimal import Decimal
from typing import Dict

from inv_trader.core.checks import typechecking
from inv_trader.model.enums import Venue, Resolution, QuoteType, OrderSide, OrderType, OrderStatus
from inv_trader.model.objects import Symbol, BarType, Bar
from inv_trader.model.order import Order
from inv_trader.model.events import Event, OrderEvent
from inv_trader.model.events import OrderSubmitted, OrderAccepted, OrderRejected, OrderWorking
from inv_trader.model.events import OrderExpired, OrderModified, OrderCancelled, OrderCancelReject
from inv_trader.model.events import OrderPartiallyFilled, OrderFilled
from inv_trader.strategy import TradeStrategy

StrategyId = str
OrderId = str

UTF8 = 'utf-8'
ORDER_EVENT_BUS = 'order_events'


class ExecutionClient:
    """
    The abstract base class for all execution clients.
    """

    __metaclass__ = abc.ABCMeta

    @typechecking
    def __init__(self):
        """
        Initializes a new instance of the ExecutionClient class.
        """
        self._registered_strategies = {}  # type: Dict[StrategyId, callable]
        self._order_index = {}            # type: Dict[OrderId, StrategyId]

    @typechecking
    def register_strategy(self, strategy: TradeStrategy):
        """
        Register the given strategy with the execution client.
        """
        strategy_id = str(strategy)

        if strategy_id in self._registered_strategies.keys():
            raise ValueError("The strategy must have a unique name and label.")

        self._registered_strategies[strategy_id] = strategy._update_events
        strategy._register_execution_client(self)

    @abc.abstractmethod
    def connect(self):
        """
        Connect to the execution service.
        """
        # Raise exception if not overridden in implementation.
        raise NotImplementedError("Method must be implemented in the execution client.")

    @abc.abstractmethod
    def disconnect(self):
        """
        Disconnect from the execution service.
        """
        # Raise exception if not overridden in implementation.
        raise NotImplementedError("Method must be implemented in the execution client.")

    @abc.abstractmethod
    def submit_order(
            self,
            order: Order,
            strategy_id: StrategyId):
        """
        Send a submit order request to the execution service.
        """
        # Raise exception if not overridden in implementation.
        raise NotImplementedError("Method must be implemented in the execution client.")

    @abc.abstractmethod
    def cancel_order(self, order: Order):
        """
        Send a cancel order request to the execution service.
        """
        # Raise exception if not overridden in implementation.
        raise NotImplementedError("Method must be implemented in the execution client.")

    @abc.abstractmethod
    def modify_order(self, order: Order, new_price: Decimal):
        """
        Send a modify order request to the execution service.
        """
        # Raise exception if not overridden in implementation.
        raise NotImplementedError("Method must be implemented in the execution client.")

    @typechecking
    def _register_order(
            self,
            order: Order,
            strategy_id: StrategyId):
        """
        Register the given order with the execution client.

        :param order: The order to register.
        :param strategy_id: The strategy id to register with the order.
        """
        if order.id in self._order_index.keys():
            raise ValueError(f"The order does not have a unique id.")

        self._order_index[order.id] = strategy_id

    @typechecking
    def _on_event(self, event: Event):
        """
        Handle events received from the execution service.
        """
        # If event order id contained in order index then send to strategy.
        if isinstance(event, OrderEvent):
            order_id = event.order_id
            if order_id not in self._order_index.keys():
                self._log(
                    f"[Warning] The given event order id not contained in order index {order_id}")
                return

            strategy_id = self._order_index[order_id]
            self._registered_strategies[strategy_id](event)

    @staticmethod
    @typechecking
    def _log(message: str):
        """
        Log the given message (if no logger then prints).

        :param message: The message to log.
        """
        print(f"ExecClient: {message}")


class LiveExecClient(ExecutionClient):
    """
    Provides a live execution client for trading strategies.
    """

    @typechecking
    def __init__(
            self,
            host: str='localhost',
            port: int=6379):
        """
        Initializes a new instance of the LiveExecClient class.
        The host and port parameters are for the order event subscription
        channel.

        :param host: The redis host IP address (default=127.0.0.1).
        :param port: The redis host port (default=6379).
        """
        super().__init__()
        self._host = host
        self._port = port
        self._client = None
        self._pubsub = None
        self._pubsub_thread = None

    @property
    def is_connected(self) -> bool:
        """
        :return: True if the client is connected, otherwise false.
        """
        if self._client is None:
            return False

        try:
            self._client.ping()
        except ConnectionError:
            return False

        return True

    def connect(self):
        """
        Connect to the execution service and create a pub/sub server.
        """
        self._client = redis.StrictRedis(host=self._host, port=self._port, db=0)
        self._pubsub = self._client.pubsub()
        self._pubsub.subscribe(**{ORDER_EVENT_BUS: self._order_event_handler})

        self._log(f"Connected to execution service at {self._host}:{self._port}.")

    def disconnect(self):
        """
        Disconnect from the local pub/sub server and the execution service.
        """
        if self._pubsub is not None:
            self._pubsub.unsubscribe(ORDER_EVENT_BUS)

        if self._pubsub_thread is not None:
            self._pubsub_thread.stop()
            time.sleep(0.100)  # Allows thread to stop.
            self._log(f"Stopped PubSub thread {self._pubsub_thread}.")

        if self._client is not None:
            self._client.connection_pool.disconnect()
            self._log((f"Disconnected from execution service "
                       f"at {self._host}:{self._port}."))
        else:
            self._log("Disconnected (the client was already disconnected).")

        self._client = None
        self._pubsub = None
        self._pubsub_thread = None

    @typechecking
    def submit_order(
            self,
            order: Order,
            strategy_id: StrategyId):
        """
        Send a submit order request to the execution service.

        :param: order: The order to submit.
        :param: order: The strategy id to register the order with.
        """
        self._check_connection()
        super()._register_order(order, strategy_id)
        # TODO

    @typechecking
    def cancel_order(self, order: Order):
        """
        Send a cancel order request to the execution service.

        :param: order: The order to cancel.
        """
        self._check_connection()
        # TODO

    @typechecking
    def modify_order(
            self,
            order: Order,
            new_price: Decimal):
        """
        Send a modify order request to the execution service.

        :param: order: The order to modify.
        :param: order: The new price for the order.
        """
        self._check_connection()
        # TODO

    def _check_connection(self):
        """
        Check the connection with the live database.

        :raises: ConnectionError if the client is not connected.
        """
        if self._client is None:
            raise ConnectionError(("No connection has been established to the execution service "
                                   "(please connect first)."))
        if not self.is_connected:
            raise ConnectionError("No connection is established with the execution service.")

    @staticmethod
    @typechecking
    def _parse_order_event(event_string: str) -> OrderEvent:
        """
        Parse an OrderEvent object from the given UTF-8 string.

        :param event_string: The order event string to parse.
        :return: The parsed order event.
        """
        header_body = event_string.split(':', maxsplit=1)

        header = header_body[0]
        split_event = header_body[1].split(',')

        symbol_split = split_event[0].split('.')
        symbol = Symbol(symbol_split[0], Venue[symbol_split[1].upper()])
        order_id = split_event[1]

        if header == 'order_submitted':
            return OrderSubmitted(
                symbol,
                order_id,
                iso8601.parse_date(split_event[2]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_accepted':
            return OrderAccepted(
                symbol,
                order_id,
                iso8601.parse_date(split_event[2]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_rejected':
            return OrderRejected(
                symbol,
                order_id,
                iso8601.parse_date(split_event[2]),
                split_event[3],
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_working':
            return OrderWorking(
                symbol,
                order_id,
                split_event[2],
                iso8601.parse_date(split_event[3]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_cancelled':
            return OrderCancelled(
                symbol,
                order_id,
                iso8601.parse_date(split_event[2]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_cancel_reject':
            return OrderCancelReject(
                symbol,
                order_id,
                iso8601.parse_date(split_event[2]),
                split_event[3],
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_modified':
            return OrderModified(
                symbol,
                order_id,
                split_event[2],
                Decimal(split_event[3]),
                iso8601.parse_date(split_event[4]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_expired':
            return OrderExpired(
                symbol,
                order_id,
                iso8601.parse_date(split_event[2]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_filled':
            return OrderFilled(
                symbol,
                order_id,
                split_event[2],
                split_event[3],
                OrderSide[split_event[4].upper()],
                int(split_event[5]),
                Decimal(split_event[6]),
                iso8601.parse_date(split_event[7]),
                uuid.uuid4(),
                datetime.utcnow())
        elif header == 'order_partially_filled':
            return OrderPartiallyFilled(
                symbol,
                order_id,
                split_event[2],
                split_event[3],
                OrderSide[split_event[4].upper()],
                int(split_event[5]),
                int(split_event[6]),
                Decimal(split_event[7]),
                iso8601.parse_date(split_event[8]),
                uuid.uuid4(),
                datetime.utcnow())
        else:
            raise ValueError("The order event is invalid and cannot be parsed.")

    @typechecking
    def _order_event_handler(self, message: Dict):
        """"
        Handle the order event message by parsing to an OrderEvent and sending
        to the registered strategy.
        """
        # If no registered strategies then print message to console.
        if len(self._registered_strategies) == 0:
            print(f"Received message {message['channel'].decode(UTF8)} "
                  f"{message['data'].decode(UTF8)}")

        order_event = self._parse_order_event(message['data'].decode(UTF8))

        self._on_event(order_event)
