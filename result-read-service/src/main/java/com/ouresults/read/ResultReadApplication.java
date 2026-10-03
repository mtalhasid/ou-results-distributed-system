package com.ouresults.read;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class ResultReadApplication {
    public static void main(String[] args) {
        SpringApplication.run(ResultReadApplication.class, args);
    }
}
