package com.deepseek.harness.android.network

class DshTransportException(
    message: String,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

class DshBusinessException(
    val code: String,
    message: String,
) : IllegalStateException("$code: $message")
