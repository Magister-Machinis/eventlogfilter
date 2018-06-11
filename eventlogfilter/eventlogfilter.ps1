param(
[parameter(mandatory=$true)][string]$path=$(throw "target evtx file"),
[parameter(mandatory=$true)][string]$ids=$(throw "ids to seach for, comma separated, no spaces"),
[parameter(mandatory=$true)][string]$dest=$(throw "dest folder for results")
)
$start = get-date #little timing mechanism
$conc = 6
$runspacepool = [RunspaceFactory ]::CreateRunspacePool(1,$conc)
$path = resolve-path $path
$dest = resolve-path $dest
$test = ($path -split"/.")[-1]

if($test -eq "evt")
{
	Write-Host "Converting evt to evtx"
	wevtutil epl $path ".\converted.evtx" /lf:true
	$path = Resolve-Path ".\converted.evtx"
}

$EVHASHlist = @()
$path
$ids = $ids.split(",")
md $dest
$ipdest = join-path -path $dest -childpath "IPS.txt"
$dest = join-path -path $dest -childpath "filteredresults.csv"
$dest
$ids
Write-Host "Ingesting logs, this may take some time"
$EVEE = get-winevent -path $path | where {$ids.contains($_.id)}

[scriptblock]$translateblock={
	param(
	$item
	)

	$ipv6 = [regex]"(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"
	$ipv4 = [regex]"\b((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b"
	$EVXML = [xml]$item.toxml()
	$EVHASHlist += @{ID = $EVXML.event.system.eventid; TIME = [datetime]$EVXML.event.system.timecreated.systemtime; Host=$EVXML.event.system.Computer; CorellationID=$EVXML.event.system.correlation.activityid}
		$temp= @()
		foreach($item2 in $(([regex]::match($item.message,$ipv4)).Value))
		{
			$temp+= $item2 +","
			
		}
		foreach($item2 in $(([regex]::match($item.message,$ipv6)).Value))
		{
			$temp+= $item2 +","
			
		}
		$count =0
		for(;$count -lt $temp.Count;$count++)
		{
			$temp[$count].replace(",,","")
		}
		$temp = $temp | sort -Unique
		$EVHASHlist.add('IP',$temp)

		Return @{'IP'=$temp; 'data'=$EVHASHlist}
}
$("ID`tHost`tTime`tCorellationID`tIP") | out-file -filepath $dest
$("IP") | out-file -FilePath $ipdest
$count =0
$runspacepool.Open()
$jobs = @()
foreach($item in $EVEE)
{
	$percent = ($count / $EVEE.Count) * 100
	write-progress -id 1 -activity "Translating Events: " -status "=][=  $count of $($EVEE.Count)" -percentcomplete $percent 
	$count++
	
	$job=[powershell]::Create().AddScript($translateblock).AddArgument($item)
	$job.RunspacePool = $runspacepool
	$jobs += New-Object PSObject -Property @{
		Pipe = $job
		Result = $job.BeginInvoke()
		}  
    
}

Write-Host "Waiting for translation to conclude"

Do {
	
	write-progress -id 1 -activity $("Number remaining: " + $($jobs.Result.IsCompleted -contains $false | Group-Object -AsHashTable -AsString)['false'].Count) -percentcomplete $(100-(($($jobs.Result.IsCompleted -contains $false | Group-Object -AsHashTable -AsString)['false'].Count)/$jobs.Count)*100)
	Start-Sleep -Seconds 1
} While ( $jobs.Result.IsCompleted -contains $false )
Write-Host "Complete, writing to file"
$count =0
$IPlist = @()
$EVList = @()
foreach($job in $jobs)
{
	$percent = ($count / $jobs.Count) * 100
	write-progress -id 1 -activity "Retrieving Events: " -status "=][=  $count of $($jobs.Count)" -percentcomplete $percent 
	$count++

	
	$temp= $job.Pipe.EndInvoke($job.Result)
	$IPlist += $temp.IP
	$EVList += [string]$($temp.data.ID + "`t" + $temp.data.Host + "`t" + $temp.data.Time +"`t"+$temp.data.CorellationID+"`t"+$temp.data.IP)

}
Write-Host "Retrieval complete"
$IPlist | sort -unique | out-file -filepath $ipdest -append
$EVList | out-file -filepath $dest -append

$end = get-date
$times= $end - $start

write-host "Time taken:"
$times
Read-Host -Prompt "Press Enter to exit"