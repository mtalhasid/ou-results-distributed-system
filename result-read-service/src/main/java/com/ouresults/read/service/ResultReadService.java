package com.ouresults.read.service;

import com.ouresults.read.dto.ResultResponse;

import java.util.List;

public interface ResultReadService {
    List<ResultResponse> findByRollNo(String rollNo);
}
