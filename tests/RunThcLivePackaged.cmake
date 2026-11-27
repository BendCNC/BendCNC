if(NOT DEFINED THC_EXE OR NOT EXISTS "${THC_EXE}")
    message(FATAL_ERROR "Missing packaged executable for THC live verification")
endif()
execute_process(
    COMMAND "${THC_EXE}" --offline-validation --verify-thc-live-integration
        --tab=4 --run-exit-after-ms=10000
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE errors
    TIMEOUT 15
)
message("${output}${errors}")
if(NOT "${result}" STREQUAL "0"
   OR NOT "${output}${errors}" MATCHES "THC-LIVE-INTEGRATION PASS"
   OR "${output}${errors}" MATCHES "THC-LIVE-INTEGRATION FAIL")
    message(FATAL_ERROR "THC packaged check failed (exit=${result}); both clean exit and PASS are required")
endif()