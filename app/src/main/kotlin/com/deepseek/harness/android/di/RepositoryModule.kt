package com.deepseek.harness.android.di

import com.deepseek.harness.android.domain.repository.ChatRepository
import com.deepseek.harness.android.harness.HarnessRepositoryImpl
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindChatRepository(
        implementation: HarnessRepositoryImpl,
    ): ChatRepository
}
