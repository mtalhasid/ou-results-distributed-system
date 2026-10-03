package com.ouresults.read.service;

public class ShardUnavailableException extends RuntimeException {
    public ShardUnavailableException(String shard, Throwable cause) {
        super("Database shard " + shard + " is temporarily unavailable.", cause);
    }
}
