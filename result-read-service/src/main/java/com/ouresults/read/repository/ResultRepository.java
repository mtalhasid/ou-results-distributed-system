package com.ouresults.read.repository;

import com.ouresults.read.entity.ResultEntity;
import com.ouresults.read.entity.ResultId;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ResultRepository extends JpaRepository<ResultEntity, ResultId> {
    @Query("""
            select result
            from ResultEntity result
            join fetch result.exam
            where result.id.rollNo = :rollNo and result.published = true
            order by result.id.semester desc
            """)
    List<ResultEntity> findPublishedByRollNo(@Param("rollNo") String rollNo);
}
