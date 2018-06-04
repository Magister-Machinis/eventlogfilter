param(
[parameter(mandatory=$true)][string]$path=$(throw "target evtx file"),
[parameter(mandatory=$true)][string]$id=$(throw "ids to seach for, comma separated, no spaces"),
[parameter(mandatory=$true)][string]$dest=$(throw "dest folder for results")
)
$conc = 6
$runspacepool = [RunspaceFactory ]::CreateRunspacePool(1,$conc)
$path = resolve-path $path
$dest = resolve-path $dest
$EVHASHlist = @()
$path
$ids = $ids.split(",")
md $dest
$ipdest = join-path -path $dest -childpath "IPS.txt"
$dest = join-path -path $dest -childpath "filteredresults.csv"
$dest
$ids

$EVEE = get-winevent -path $path | where {$ids.contains($_.id)}

[scriptblock]$translateblock={
param(
[string]$ipdest,
[string]$filedest,
$item
)

	function Test-FileLock {
	  param (
		[parameter(Mandatory=$true)][string]$Path
	  )

	  $oFile = New-Object System.IO.FileInfo $Path

	  if ((Test-Path -Path $Path) -eq $false) {
		return $false
	  }

	  try {
		$oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

		if ($oStream) {
		  $oStream.Close()
		}
		$false
	  } catch {
		# file is locked by a process.
		return $true
	  }
	}
	$ipv6 = [regex]"(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"
	$ipv4 = [regex]"\b((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b"
	$EVXML = [xml]$item.toxml()
	$EVHASHlist += @{ID = $EVXML.event.system.eventid; TIME = [datetime]$EVXML.event.system.timecreated.systemtime; Host=$EVXML.event.system.Computer; CorellationID=$EVXML.event.system.correlation.activityid}
		$temp= $null
		foreach($item in([regex]::match($EVEE.message,$ipv4)).Value)
		{
			$temp+=$item+","
			$IPlist+=$item
		}
		foreach($item in([regex]::match($EVEE.message,$ipv6)).Value)
		{
			$temp+=$item+","
			$IPlist+=$item
		}
		$temp = $temp | sort -Unique
		$EVHASHlist.add('IP',$temp)

		Return @($temp, $EVHASHlist)
}
$("Host`tTime`tCorellationID`tIP") | out-file -filepath $dest
$("IP") | out-file -FilePath $ipdest
$count =0
$runspacepool.Open()
$jobs = @()
foreach($item in $EVEE)
{
	$percent = ($count / $EVEE.Count) * 100
	write-progress -id 1 -activity "Translating Events: " -status "=][=  $count of $($EVEE.Count)" -percentcomplete $percent 
	$count++
	
	$job=[powershell]::Create().AddScipt($translateblock).AddArgument($ipdest).AddArgument($dest).AddArgument($item)
	$job.RunspacePool = $runspacepool
	$jobs += New-Object PSObject -Property @{
		Pipe = $job
		Result = $job.BeginInvoke()
		}  
    
}

Write-Host "Waiting for translation to conclude"

Do {
   Write-Host "." -NoNewline
   Start-Sleep -Seconds 1
} While ( $jobs.Result.IsCompleted -contains $false )
Write-Host "Complete, writing to file"
foreach($job in $jobs)
{
	$temp= $job.Pip.EndInvoke($job.Result)
	$temp[0] | Out-File -FilePath $ipdest -Append
	$($temp[1].Host + "`t" + $temp[1].Time +"`t"+$temp[1].CorellationID+"`t"+$temp[1].IP) | Out-File -FilePath $dest -Append

}
$IPlist = get-content $ipdest
$IPlist | sort -unique | out-file -filepath	$ipdest





