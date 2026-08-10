function Enter-YoooniUpdateMutex {
  param(
    [string]$Name = 'Local\YoooniTeamToolsUpdate',
    [int]$TimeoutMilliseconds = 0
  )

  $mutex = New-Object System.Threading.Mutex($false, $Name)
  try {
    $acquired = $mutex.WaitOne($TimeoutMilliseconds)
  }
  catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
  }

  if ($acquired) { return $mutex }
  $mutex.Dispose()
  return $null
}

function Exit-YoooniUpdateMutex {
  param([System.Threading.Mutex]$Mutex)
  if ($null -eq $Mutex) { return }
  try { $Mutex.ReleaseMutex() }
  catch [System.ApplicationException] { }
  finally { $Mutex.Dispose() }
}
