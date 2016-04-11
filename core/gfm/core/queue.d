module gfm.core.queue;

import std.range;

import core.sync.mutex,
       core.sync.semaphore;

import gfm.core.memory;

// what to do when capacity is exceeded?
private enum OverflowPolicy
{
    GROW,
    CRASH,
    DROP
}

/**

    Doubly-indexed queue, can be used as a FIFO or stack.

    Bugs:
        Doesn't call struct destructors, don't scan memory.
        You should probably only put POD types in them.
 */
final class QueueImpl(T, OverflowPolicy overflowPolicy)
{
    public
    {
        /// Create a QueueImpl with specified initial capacity.
        this(size_t initialCapacity) nothrow
        {
            _data.length = initialCapacity;
            clear();
        }

        /// Returns: true if the queue is full.
        @property bool isFull() pure const nothrow
        {
            return _count == capacity;
        }

        /// Returns: capacity of the queue.
        @property size_t capacity() pure const nothrow
        {
            return _data.length;
        }

        /// Adds an item on the back of the queue.
        void pushBack(T x) nothrow
        {
            checkOverflow!popFront();
           _data[(_first + _count) % _data.length] = x;
            ++_count;
        }

        /// Adds an item on the front of the queue.
        void pushFront(T x) nothrow
        {
            checkOverflow!popBack();
            ++_count;
            _first = (_first - 1 + _data.length) % _data.length;
            _data[_first] = x;
        }

        /// Removes an item from the front of the queue.
        /// Returns: the removed item.
        T popFront() nothrow
        {
            crashIfEmpty();
            T res = _data[_first];
            _first = (_first + 1) % _data.length;
            --_count;
            return res;
        }

        /// Removes an item from the back of the queue.
        /// Returns: the removed item.
        T popBack() nothrow
        {
            crashIfEmpty();
            --_count;
            return _data[(_first + _count) % _data.length];
        }

        /// Removes all items from the queue.
        void clear() nothrow
        {
            _first = 0;
            _count = 0;
        }

        /// Returns: number of items in the queue.
        size_t length() pure const nothrow
        {
            return _count;
        }

        /// Returns: item at the front of the queue.
        T front() pure
        {
            crashIfEmpty();
            return _data[_first];
        }

        /// Returns: item on the back of the queue.
        T back() pure
        {
            crashIfEmpty();
            return _data[(_first + _count + _data.length - 1) % _data.length];
        }

        /// Returns: item index from the queue.
        T opIndex(size_t index)
        {
            // crash if index out-of-bounds (not recoverable)
            if (index > _count)
                assert(0);

            return _data[(_first + index) % _data.length];
        }

        /// Returns: random-access range over the whole queue.
        Range opSlice() nothrow
        {
            return Range(this);
        }

        /// Returns: random-access range over a queue sub-range.
        Range opSlice(size_t i, size_t j) nothrow
        {
            // verify that all elements are in bound
            if (i != j && i >= _count)
                assert(false);

            if (j > _count)
                assert(false);

            if (j < i)
                assert(false);

            return Range(this);
        }

        // range type, random access
        static struct Range
        {
        nothrow:
            public
            {
                this(QueueImpl queue) pure
                {
                    this(queue, 0, queue._count);
                    _first = queue._first;
                    _count = queue._count;
                }

                this(QueueImpl queue, size_t index, size_t count) pure
                {
                    _index = index;
                    _data = queue._data;
                    _first = (queue._first + index) % _data.length;
                    _count = _count;
                }

                @property bool empty() pure const
                {
                    return _index >= _count;
                }

                void popFront()
                {
                    _index++;
                }

                @property T front() pure
                {
                    return _data[(_first + _index) % _data.length];
                }

                void popBack()
                {
                    _count--;
                }

                @property T back() pure
                {
                    return _data[(_first + _count - 1) % _data.length];
                }

                @property Range save()
                {
                    return this;
                }

                T opIndex(size_t i)
                {
                    // crash if index out-of-bounds of the range (not recoverable)
                    if (i > _count)
                        assert(0);

                    return _data[(_first + _index + i) % _data.length];
                }

                @property size_t length() pure
                {
                    return _count;
                }

                alias length opDollar;
            }

            private
            {
                size_t _index;
                T[] _data;
                size_t _first;
                size_t _count;
            }
        }
    }

    private
    {
        void crashIfEmpty()
        {
            // popping if empty is not a recoverable error
            if (_count == 0)
                assert(false);
        }

        // element lie from _first to _first + _count - 1 index, modulo the allocated size
        T[] _data;
        size_t _first;
        size_t _count;

        void checkOverflow(alias popMethod)() nothrow
        {
            if (isFull())
            {
                static if (overflowPolicy == OverflowPolicy.GROW)
                    extend();

                static if (overflowPolicy == OverflowPolicy.CRASH)
                    assert(false); // not recoverable to overflow such a queue

                static if (overflowPolicy == OverflowPolicy.DROP)
                    popMethod();
            }
        }

        void extend() nothrow
        {
            size_t newCapacity = capacity * 2;
            if (newCapacity < 8)
                newCapacity = 8;

            assert(newCapacity >= _count + 1);

            T[] newData = new T[newCapacity];

            auto r = this[];
            size_t i = 0;
            while (!r.empty())
            {
                newData[i] = r.front();
                r.popFront();
                ++i;
            }
            _data = newData;
            _first = 0;
        }
    }
}

static assert (isRandomAccessRange!(Queue!int.Range));

unittest
{
    // fifo
    {
        int N = 7;
        auto fifo = new Queue!int(N);
        foreach(n; 0..N)
            fifo.pushBack(n);

        assert(fifo.back() == N - 1);
        assert(fifo.front() == 0);

        foreach(n; 0..N)
        {
            assert(fifo.popFront() == n);
        }
    }

    // stack
    {
        int N = 7;
        auto fifo = new Queue!int(N);
        foreach(n; 0..N)
            fifo.pushBack(n);

        foreach(n; 0..N)
            assert(fifo.popBack() == N - 1 - n);
    }
}


/**

A queue that can only grow.


See_also: $(LINK2 #QueueImpl, QueueImpl)

*/
template Queue(T)
{
    alias QueueImpl!(T, OverflowPolicy.GROW) Queue;
}

/**

A fixed-sized queue that will crash on overflow.

See_also: $(LINK2 #QueueImpl, QueueImpl)


*/
template FixedSizeQueue(T)
{
    alias QueueImpl!(T, OverflowPolicy.CRASH) FixedSizeQueue;
}

/**

Ring buffer, it drops if its capacity is exceeded.

See_also: $(LINK2 #QueueImpl, QueueImpl)

*/
template RingBuffer(T)
{
    alias QueueImpl!(T, OverflowPolicy.DROP) RingBuffer;
}

/**
    Locked queue for inter-thread communication.
    Support multiple writers, multiple readers.
    Blocks threads either when empty or full.

    See_also: $(LINK2 #Queue, Queue)
 */
deprecated("LockedQueue has been moved to package dplug:core, use it instead") final class LockedQueue(T)
{
    public
    {
        /// Creates a locked queue with an initial capacity.
        this(size_t capacity)
        {
            _queue = new FixedSizeQueue!T(capacity);
            _rwMutex = new Mutex();
            _readerSemaphore = new Semaphore(0);
            _writerSemaphore = new Semaphore(cast(uint)capacity);
        }

        ~this()
        {
            debug ensureNotInGC("LockedQueue");
            clear();
            _rwMutex.destroy();
            _readerSemaphore.destroy();
            _writerSemaphore.destroy();
        }

        /// Returns: Capacity of the locked queue.
        size_t capacity() const
        {
            // no lock-required as capacity does not change
            return _queue.capacity;
        }

        /// Push an item to the back, block if queue is full.
        void pushBack(T x)
        {
            _writerSemaphore.wait();
            {
                _rwMutex.lock();
                _queue.pushBack(x);
                _rwMutex.unlock();
            }
            _readerSemaphore.notify();
        }

        /// Push an item to the front, block if queue is full.
        void pushFront(T x)
        {
            _writerSemaphore.wait();
            {
                _rwMutex.lock();
                _queue.pushFront(x);
                _rwMutex.unlock();
            }
            _readerSemaphore.notify();
        }

        /// Pop an item from the front, block if queue is empty.
        T popFront()
        {
            _readerSemaphore.wait();
            _rwMutex.lock();
            T res = _queue.popFront();
            _rwMutex.unlock();
            _writerSemaphore.notify();
            return res;
        }

        /// Pop an item from the back, block if queue is empty.
        T popBack()
        {
            _readerSemaphore.wait();
            _rwMutex.lock();
            T res = _queue.popBack();
            _rwMutex.unlock();
            _writerSemaphore.notify();
            return res;
        }

        /// Tries to pop an item from the front immediately.
        /// Returns: true if an item was returned, false if the queue is empty.
        bool tryPopFront(out T result)
        {
            if (_readerSemaphore.tryWait())
            {
                _rwMutex.lock();
                result = _queue.popFront();
                _rwMutex.unlock();
                _writerSemaphore.notify();
                return true;
            }
            else
                return false;
        }

        /// Tries to pop an item from the back immediately.
        /// Returns: true if an item was returned, false if the queue is empty.
        bool tryPopBack(out T result)
        {
            if (_readerSemaphore.tryWait())
            {
                _rwMutex.lock();
                result = _queue.popBack();
                _rwMutex.unlock();
                _writerSemaphore.notify();
                return true;
            }
            else
                return false;
        }

        /// Removes all locked queue items.
        void clear()
        {
            while (_readerSemaphore.tryWait())
            {
                _rwMutex.lock();
                _queue.popBack();
                _rwMutex.unlock();
                _writerSemaphore.notify();
            }
        }
    }

    private
    {
        FixedSizeQueue!T _queue;
        Mutex _rwMutex;
        Semaphore _readerSemaphore, _writerSemaphore;
    }
}

/+
unittest
{
    import std.stdio;
    auto lq = new LockedQueue!int(3);
    scope(exit) lq.destroy();
    lq.clear();
    lq.pushFront(2);
    lq.pushBack(3);
    lq.pushFront(1);

    // should contain [1 2 3] here
    assert(lq.popBack() == 3);
    assert(lq.popFront() == 1);
    int res;
    if (lq.tryPopFront(res))
    {
        assert(res == 2);
    }
}
+/
