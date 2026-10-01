package com.ouresults.read.config;

import org.springframework.stereotype.Component;

@Component
public class ShardContext {
    private final ThreadLocal<String> currentShard = new ThreadLocal<>();

    public String currentShard() {
        return currentShard.get();
    }

    public String useShard(String shard) {
        String previous = currentShard.get();
        currentShard.set(shard);
        return previous;
    }

    public void restore(String previous) {
        if (previous == null) {
            currentShard.remove();
        } else {
            currentShard.set(previous);
        }
    }
}
