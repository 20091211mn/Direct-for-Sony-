package com.example.ps4_sender

import android.app.job.JobParameters
import android.app.job.JobService

/** Runs every ~15 minutes (JobScheduler), even when the app is closed. */
class CheckJobService : JobService() {

    override fun onStartJob(params: JobParameters?): Boolean {
        Thread {
            try {
                NoticeChecker.runAndRecord(this)
            } finally {
                jobFinished(params, false)
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = false
}
