package com.deepseek.harness.android.di

import com.deepseek.harness.android.BuildConfig
import com.deepseek.harness.android.harness.DshBackoffDelay
import com.deepseek.harness.android.harness.ExponentialDshBackoffDelay
import com.deepseek.harness.android.network.DshEventSocket
import com.deepseek.harness.android.network.DshRpcClient
import com.deepseek.harness.android.network.OkHttpDshEventSocket
import com.deepseek.harness.android.network.OkHttpDshRpcClient
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.util.concurrent.TimeUnit
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    /** Injectable IO dispatcher shared by harness-owned background scopes. */
    @Provides
    @Singleton
    fun provideIoDispatcher(): CoroutineDispatcher = Dispatchers.IO

    @Provides
    @Singleton
    fun provideDshBackoffDelay(): DshBackoffDelay = ExponentialDshBackoffDelay()

    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        coerceInputValues = true
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    @Provides
    @Singleton
    fun provideDshRpcClient(
        client: OkHttpClient,
        json: Json,
    ): DshRpcClient = OkHttpDshRpcClient(
        baseUrl = BuildConfig.DSH_BASE_URL.toHttpUrl(),
        client = client,
        json = json,
    )

    @Provides
    @Singleton
    fun provideDshEventSocket(
        client: OkHttpClient,
        json: Json,
    ): DshEventSocket = OkHttpDshEventSocket(
        baseUrl = BuildConfig.DSH_BASE_URL.toHttpUrl(),
        client = client,
        json = json,
    )
}
