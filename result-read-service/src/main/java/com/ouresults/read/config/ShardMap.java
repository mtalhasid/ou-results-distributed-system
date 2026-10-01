package com.ouresults.read.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

@Component
public class ShardMap {
    private final Map<String, String> colleges;

    public ShardMap(@Value("${shard-map-path:/app/config/shard-map.yml}") String path) {
        try (var input = Files.newInputStream(Path.of(path))) {
            var yaml = new ObjectMapper(new YAMLFactory()).readValue(input, ShardMapDocument.class);
            this.colleges = Map.copyOf(yaml.colleges());
        } catch (IOException exception) {
            throw new IllegalStateException("Could not load shard map from " + path, exception);
        }
    }

    public String shardFor(String collegeCode) {
        String shard = colleges.get(collegeCode);
        if (shard == null) {
            throw new UnknownCollegeException(collegeCode);
        }
        return shard;
    }

    private record ShardMapDocument(Map<String, String> colleges) {}

    public static class UnknownCollegeException extends RuntimeException {
        public UnknownCollegeException(String collegeCode) {
            super("Unknown college code: " + collegeCode);
        }
    }
}
