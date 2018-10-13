module Session

import HPack
import HPack: DynamicTable
import HttpCommon: Headers
import HTTP2.Frame
import HTTP2.Frame: ContinuationFrame, DataFrame, GoawayFrame, HeadersFrame, PingFrame, PriorityFrame, PushPromiseFrame, RstStreamFrame, SettingsFrame, WindowUpdateFrame

@enum STREAM_STATE IDLE=1 RESERVED_LOCAL=2 RESERVED_REMOTE=3 OPEN=4 HALF_CLOSED_REMOTE=5 HALF_CLOSED_LOCAL=6 CLOSED=7

mutable struct Priority
    dependent_stream_identifier::UInt32
    weight::UInt8
end

## Actions, which should be feeded in to `in` channel.

struct ActPromise
    stream_identifier::UInt32
    promised_stream_identifier::UInt32
    headers::Headers
end

struct ActSendHeaders
    stream_identifier::UInt32
    headers::Headers
    is_end_stream::Bool
end

struct ActSendData
    stream_identifier::UInt32
    data::Array{UInt8, 1}
    is_end_stream::Bool
end

## Events, which should be fetched from `out` channel.

struct EvtPromise
    stream_identifier::UInt32
    promised_stream_identifier::UInt32
    headers::Headers
end

struct EvtRecvHeaders
    stream_identifier::UInt32
    headers::Headers
    is_end_stream::Bool
end

struct EvtRecvData
    stream_identifier::UInt32
    data::Array{UInt8, 1}
    is_end_stream::Bool
end

struct EvtGoaway end

mutable struct HTTPStream
    stream_identifier::UInt32
    state::STREAM_STATE
    window_size::UInt32
    priority::Union{Priority, Nothing}
end

mutable struct HTTPSettings
    push_enabled::Bool
    max_concurrent_streams::Union{UInt, Nothing}
    initial_window_size::UInt
    max_frame_size::UInt
    max_header_list_size::Union{UInt, Nothing}
end

HTTPSettings() = HTTPSettings(true, nothing, 65535, 16384, nothing)

mutable struct HTTPConnection
    dynamic_table::DynamicTable
    streams::Array{HTTPStream, 1}
    window_size::UInt32
    isclient::Bool
    last_stream_identifier::UInt32
    settings::HTTPSettings
    closed::Bool

    channel_act::Channel{Any} # Process actions
    channel_act_raw::Channel{Any} # Process raw frames
    channel_evt::Channel{Any} # Output events
    channel_evt_raw::Channel{Any} # Output raw frames

    ## actions -> channel_act -> channel_act_raw -> io
    ## io -> channel_evt_raw -> channel_evt -> events
end

HTTPConnection(isclient) = HTTPConnection(HPack.new_dynamic_table(),
                                          Array{HTTPStream, 1}(),
                                          65535,
                                          isclient,
                                          isclient ? 1 : 2,
                                          HTTPSettings(),
                                          false,

                                          Channel(32),
                                          Channel(32),
                                          Channel(32),
                                          Channel(32))

function next_free_stream_identifier(connection::HTTPConnection)
    return connection.last_stream_identifier + 2
end

include("Session/utils.jl")
include("Session/settings.jl")
include("Session/errors.jl")
include("Session/states.jl")
include("Session/handlers.jl")
include("Session/channels.jl")

function new_connection(buffer; isclient::Bool=true, skip_preface=false)
    connection = HTTPConnection(isclient)
    initialize_loop_async(connection, buffer; skip_preface=skip_preface)
    return connection
end

function put_act!(connection::HTTPConnection, act)
    put!(connection.channel_act, act)
end

function take_evt!(connection::HTTPConnection)
    return take!(connection.channel_evt)
end

end
