package com.ouresults.gateway.config;

import java.util.Map;

public record CollegeCatalog(Map<String, String> colleges) {
    public CollegeCatalog {
        colleges = Map.copyOf(colleges);
    }
}
