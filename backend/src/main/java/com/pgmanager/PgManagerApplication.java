package com.pgmanager;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class PgManagerApplication {
    public static void main(String[] args) {
        SpringApplication.run(PgManagerApplication.class, args);
    }
}
