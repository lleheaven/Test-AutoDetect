param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [String[]]$Email,
    [Switch]$Hybrid,
    [Switch]$TestEXOAutoDV2,
    [Switch]$TestOnPremAutoDV2,
    [String]$CustomAutoD
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$emailAddress = $Email.Split("@")
$headers = @{'Accept' = 'application/json'}

#Get federation provider
function Get-FederationProvider {
    process{
        try {
            Write-Host
            Write-Host "Get Federation Provider to see if it's a sovereign cloud account." -ForegroundColor Green
            $getFederationProviderServiceUrl =  "https://odc.officeapps.live.com/odc/v2.1/federationprovider?domain=$($EmailAddress[1])"
            $getFederationProviderResponse = Invoke-WebRequest -Uri $getFederationProviderServiceUrl -Headers $headers -Method GET -UseBasicParsing
            $getFederationProviderResult = $getFederationProviderResponse.Content | ConvertFrom-Json
            $configProvider = $getFederationProviderResult.configProviderName
			
			Write-Host $getFederationProviderResult.configProviderName -ForegroundColor Green

            #Check if it returns configProviderName. If not, it should not be a sovereign cloud account.
            #Conitnue with AutoDetect.
            if(!$configProvider) {
                Write-Host
                Write-Host "It's not a sovereign cloud account, continue with AutoDetect." -ForegroundColor Green
                Test-AutoDetect
            }
            else {
                switch ($configProvider) {
                    "gcc.microsoftonline.com" { Write-Host "It's detected as a GCC Moderate account." -ForegroundColor Green }
                    "microsoftonline.us" { Write-Host "It's detected as a GCC High account." -ForegroundColor Green }
                    "microsoftonline.mil" { Write-Host "It's detected as a DoD account." -ForegroundColor Green }
                    "partner.microsoftonline.cn" { Write-Host "It's detected as a Gallatin account." -ForegroundColor Green }
                    "microsoftonline.de" { Write-Host "It's detected as a Black Forest account." -ForegroundColor Green }
                }
                Get-ServiceEndpoints
            }
        }
        catch {
            $_.Exception
        }
    }
}

#Get EWS, AutoDiscover endpoints
function Get-ServiceEndpoints {
    process{
        try {
            Write-Host
            Write-Host "Calling OfficeClient service to get services endpoints." -ForegroundColor Yellow
            $configServiceUrl = "https://officeclient.microsoft.com/config16processed?rs=en-us&build=16.0.7612"
            $getServiceEndpointsResponse = Invoke-WebRequest -Uri "$($configServiceUrl)&services=ExchangeAutoDiscoverV2Url,ExchangeWebService&fp=$($configProvider)" -Headers $headers -Method GET -UseBasicParsing 
            $getServiceEndpointsResult = $getServiceEndpointsResponse.Content | ConvertFrom-Json
            $exchangeWebServiceUrl = $getServiceEndpointsResult."o:OfficeConfig"."o:services"."o:service"[0]."o:url"
            $authorityUrl =  $getServiceEndpointsResult."o:OfficeConfig"."o:services"."o:service"[0]."o:ticket"."@o:authorityUrl"
            $resourceId =  $getServiceEndpointsResult."o:OfficeConfig"."o:services"."o:service"[0]."o:ticket"."@o:resourceId"
            $exchangeAutoDiscoverV2Url = $getServiceEndpointsResult."o:OfficeConfig"."o:services"."o:service"[1]."o:url"
            Write-Host "Here are the services endpoints for this account." -ForegroundColor Yellow
            Write-Host "---------------------------------------------------------------------------------------------------------------"
            Write-Host "Email:                      " $Email
            Write-Host "Exchange WebService URL:    " $exchangeWebServiceUrl
            Write-Host "Authority URL:              " $authorityUrl
            Write-Host "Resource Id:                " $resourceId
            Write-Host "Exchange AutoDiscoverV2 URL:" $exchangeAutoDiscoverV2Url
        }
        catch {
            $_.Exception
        }
    }
}
#Call AutoDetect service
function Test-AutoDetect {
    process{
        try{
            $autoDetectURL = "https://prod-AutoDetect.outlookmobile.com/detect?protocols=eas,rest-cloud,imap,pop3,Email&timeout=13.5&services=office365,outlook,google,icloud,yahoo"
            $encodedEmailAddress = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Email))
            $authorizationHeader = @{'Authorization' = "Basic " + $encodedEmailAddress}
            $userAgent = "PowershellRuntime"
            $autoDetectResponse = Invoke-WebRequest -Uri $autoDetectURL -Headers $authorizationHeader -UserAgent $userAgent  -Method GET -UseBasicParsing 
            $autoDetectResult = $autoDetectResponse.Content | ConvertFrom-Json
            $requestId = $autoDetectResponse.Headers.'X-Request-Id'
            $responseTime = $autoDetectResponse.Headers.'X-Response-Time'
            $responseDate = $autoDetectResponse.Headers.'Date'
            $autoDV2Error = $autoDetectResponse.Headers.'X-AutoDv2-Error'
            #Write-Host $autoDetectResult
            if($autoDetectResponse.StatusCode -eq 200 ) {
                #Check if the service is Office365, if not, it needs to contact OM PG to change it
                if($autoDetectResult.services.service -eq "office365") {
                    #Check if it returns expected onprem EAS URL in the response
                    if(!!$autoDetectResult.services.onprem) {
                        #If it's true, it means AutoDetect works fine and got the EAS endpoint from AutoDv2. Output AutoDetect response.
                        Write-Host
                        Write-Host "AutoDetect detected this is a Hybrid Exchange account and it has the following services listed for the user." -ForegroundColor Green
                        Write-Host "This should have AAD pointing to Microsoft Online and On-Premises to the correct EAS URL." -ForegroundColor Yellow
                        Write-Host "---------------------------------------------------------------------------------------------------------------"
                        Write-Host "Email:          " $autoDetectResult.email
                        Write-Host "Service:        " $autoDetectResult.services.service
                        Write-Host "Azure AD:       " $autoDetectResult.services.aad
                        Write-Host "On-Premises:    " $autoDetectResult.services.onprem
                        Write-Host "X-Request-Id:   " $requestId
                        Write-Host "X-Response-Time:" $responseTime
                        Write-Host "Date:           " $responseDate
                        Write-Host
                    }
                    elseif ($autoDetectResult.services.protocol -eq "rest") {
                        #If it's true, it means it's detected as O365 account.
                        Write-Host
                        Write-Host "AutoDetect detected this is an Office 365 account and it has the following services listed for the user." -ForegroundColor Green
                        Write-Host "---------------------------------------------------------------------------------------------------------------"
                        Write-Host "Email:          " $autoDetectResult.email
                        Write-Host "Service:        " $autoDetectResult.services.service
                        Write-Host "Protocol:       " $autoDetectResult.services.protocol
                        Write-Host "Azure AD:       " $autoDetectResult.services.aad
                        Write-Host "On-Premises:    " $autoDetectResult.services.onprem
                        Write-Host "X-Request-Id:   " $requestId
                        Write-Host "X-Response-Time:" $responseTime
                        Write-Host "Date:           " $responseDate
                        Write-Host
                    }
                    else {
                        #If the procotol is not rest, it should be a known account.
                        Write-Host
                        Write-Host "There is no rest protocol detected for this mailbox in AutoDetect, but the service provider is Office365." -ForegroundColor Red
                        Write-Host "This could happen when AutoDiscoverV2 calling timed out in AutoDetect backend." -ForegroundColor Red
                        Write-Host "---------------------------------------------------------------------------------------------------------------"
                        Write-Host "Email:          " $autoDetectResult.email
                        Write-Host "Service:        " $autoDetectResult.services.service
                        Write-Host "Protocol:       " $autoDetectResult.services.protocol
                        Write-Host "Azure AD:       " $autoDetectResult.services.aad
                        Write-Host "On-Premises:    " $autoDetectResult.services.onprem
                        Write-Host "X-Request-Id:   " $requestId
                        Write-Host "X-Response-Time:" $responseTime
                        Write-Host "AutoDV2 Error:  " $autoDV2Error
                        Write-Host "Date:           " $responseDate
                        Write-Host
                    }
                }
                else {
                    #If AutoDetect doesn't return services, use protocols to recognize account type.
                    if(!$autoDetectResult.services.service) {
                            Write-Host
                            Write-Host "AutoDetect detected this account as a (an)" $autoDetectResult.protocols.protocol "account." -ForegroundColor Green
                            Write-Host "---------------------------------------------------------------------------------------------------------------"
                            Write-Host "Email:          " $autoDetectResult.email
                            Write-Host "Protocol:       " $autoDetectResult.protocols
                            Write-Host "X-Request-Id:   " $requestId
                            Write-Host "X-Response-Time:" $responseTime
                            Write-Host "Date:           " $responseDate
                            Write-Host
                    }
                    else {
                        #If AutoDetect return services, use services to recognize account type.
                        Write-Host
                        Write-Host "AutoDetect detected this account as a (an)" $autoDetectResult.services.service "account." -ForegroundColor Green
                        Write-Host "---------------------------------------------------------------------------------------------------------------"
                        Write-Host "Email:          " $autoDetectResult.email
                        Write-Host "Service:        " $autoDetectResult.services.service
                        Write-Host "Protocol:       " $autoDetectResult.services.protocol $autoDetectResult.protocols
                        Write-Host "X-Request-Id:   " $requestId
                        Write-Host "X-Response-Time:" $responseTime
                        Write-Host "Date:           " $responseDate
                        Write-Host
                    }
                }
            }
            elseif($autoDetectResponse.StatusCode -eq 202) {
                Write-Host
                Write-Host "No service or protocol found in AutoDetect yet (still searching), suggest to correct the email domain and try it later." -ForegroundColor Red
                Write-Host "---------------------------------------------------------------------------------------------------------------"
                Write-Host "Status Code:       " $autoDetectResponse.StatusCode
                Write-Host "Status Description:" $autoDetectResponse.StatusDescription
                Write-Host "X-Request-Id:      " $requestId
                Write-Host "X-Response-Time:   " $responseTime
                Write-Host "Date:          " $responseDate
                Write-Host
            }
            elseif($autoDetectResponse.StatusCode -eq 204) {
                Write-Host
                Write-Host "No service or protocol found in AutoDetect, suggest to correct the email domain." -ForegroundColor Red
                Write-Host "---------------------------------------------------------------------------------------------------------------"
                Write-Host "Status Code:       " $autoDetectResponse.StatusCode
                Write-Host "Status Description:" $autoDetectResponse.StatusDescription
                Write-Host "X-Request-Id:      " $requestId
                Write-Host "X-Response-Time:   " $responseTime
                Write-Host "Date:          " $responseDate
                Write-Host
            }
            elseif ($autoDetectResponse.StatusCode -eq 503) {
                Write-Host
                Write-Host "It looks like the service is not avaiable currently, please try again later." -ForegroundColor Red
                Write-Host "---------------------------------------------------------------------------------------------------------------"
                Write-Host "Status Code:"        $autoDetectResponse.StatusCode
                Write-Host "Status Description:" $autoDetectResponse.StatusDescription
                Write-Host "X-Request-Id:"       $requestId
                Write-Host "X-Response-Time:   " $responseTime
                Write-Host "Date:          " $responseDate
                Write-Host
            }
            else {
                Write-Host
                Write-Host "Oops...It looks like something went wrong with calling AutoDetect." -ForegroundColor Red
                Write-Host "---------------------------------------------------------------------------------------------------------------"
                Write-Host "Status Code:"        $autoDetectResponse.StatusCode
                Write-Host "Status Description:" $autoDetectResponse.StatusDescription
                Write-Host "X-Request-Id:"       $requestId
                Write-Host "X-Response-Time:   " $responseTime
                Write-Host "Date:          " $responseDate
                Write-Host
            }

        }
        catch {
            Write-Host $_.Exception
        }
    }
}

#Call OnPrem AutoDiscoverV2
function Test-OnPremAutoDV2 {
    process {
        try {
            if ($CustomAutoD) {
                $onPremAutoDV2Url = "https://$($CustomAutoD)/autodiscover/autodiscover.json?Email=$($Email)&Protocol=activesync&RedirectCount=3"
            }
            else {
                $onPremAutoDV2Url = "https://autodiscover.$($EmailAddress[1])/autodiscover/autodiscover.json?Email=$($Email)&Protocol=activesync&RedirectCount=3"
            }
            $headers = @{
                'Accept'         = 'application/json'
                'Content-Length' = '0'
            }
            $timeTaken = Measure-Command -Expression {$onPremAutoDV2Response = Invoke-WebRequest -Uri $onPremAutoDV2Url -Headers $headers -Method GET -UseBasicParsing} 
            $onPremAutoDV2Result = $onPremAutoDV2Response.Content | ConvertFrom-Json
            $milliseconds = $timeTaken.TotalMilliseconds
            $milliseconds = [Math]::Round($milliseconds, 1)
            $onPremAutoDV2Result = $onPremAutoDV2Response.Content | ConvertFrom-Json
            $requestId = $onPremAutoDV2Response.Headers.'request-id'
            Write-Host
            Write-Host "We sent an AutoDiscover Request to On-Premises for the Exchange ActiveSync Virtual Directory and below is the response" -ForegroundColor Green
            Write-Host "The response should contain the Protocol ActiveSync with a valid URL" -ForegroundColor Yellow
            Write-Host "If AutoDetect doesn't return On-Prem value for your Hybrid account, please check your firewall and Hybrid configuration," -ForegroundColor Yellow
            Write-Host "to ensure you have allowed traffic from 'outlookmobile.com'." -ForegroundColor Yellow
            Write-Host "---------------------------------------------------------------------------------------------------------------"
            Write-Host "Response Body: ", $onPremAutoDV2Result
            Write-Host "Time Taken:    ", $milliseconds, "ms"
            Write-Host "Request Id:    ", $requestId
            Write-Host
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Host
            Write-Host "We sent an AutoDiscover Request to On-Premises for the Exchange ActiveSync Virtual Directory and below is the response" -ForegroundColor Green
            Write-Host "The response should contain the Protocol ActiveSync with a valid URL" -ForegroundColor Yellow
            Write-Host "---------------------------------------------------------------------------------------------------------------"
            Write-Host "ERROR: We were unable to complete the AutoDiscover request." -ForegroundColor Red -Verbose
            Write-Host "Please ensure that autodiscover.$($EmailAddress[1]) is the correct AutoDiscover endpoint and is not being blocked by a firewall" -ForegroundColor Yellow -Verbose
            Write-Host
        }
        catch [System.Net.WebException] {
            Write-Host
            Write-Host "We sent an AutoDiscover Request to On-Premises for the Exchange ActiveSync Virtual Directory and below is the response" -ForegroundColor Green
            Write-Host "The response should contain the Protocol ActiveSync with a valid URL" -ForegroundColor Yellow
            Write-Host "---------------------------------------------------------------------------------------------------------------"
            Write-Host "ERROR: We were unable to complete the AutoDiscover request." -ForegroundColor Red -Verbose
            Write-Host "Please ensure that autodiscover.$($EmailAddress[1]) is the correct AutoDiscover endpoint and is able to be resolved in DNS" -ForegroundColor Yellow -Verbose
            Write-Host
        }        
        catch {
            Write-Host
            Write-Error $_.Exception.Message
            Write-Host            
        }
    }
}

function Test-EXOAutoDV2 {
    process{
        try {
            Write-Host
            Write-Host "Calling EXO AutoDiscover endpoint to discover the Mailbox" -ForegroundColor Green
            $exoAutoDEndpoint =  "https://outlook.office.com/autodiscover/autodiscover.json?Email=$($Email)&Protocol=ActiveSync"
            $timeTaken = Measure-Command -Expression {$exoAutoDResponse = Invoke-WebRequest -Uri $exoAutoDEndpoint -Headers $headers -Method GET -UseBasicParsing} 
            $exoAutoDResult = $exoAutoDResponse.Content | ConvertFrom-Json
            $milliseconds = $timeTaken.TotalMilliseconds
            $milliseconds = [Math]::Round($milliseconds, 1)
            $requestId = $exoAutoDResponse.Headers.'request-id'
            Write-Host
            Write-Host "We sent an AutoDiscover Request to Exchange Online AutoDiscover Endpoint and below is the response" -ForegroundColor Green
            Write-Host "The response should contain the Protocol ActiveSync with a valid URL" -ForegroundColor Yellow
            Write-Host "---------------------------------------------------------------------------------------------------------------"
            Write-Host "Response Body: ", $exoAutoDResult
            Write-Host "Time Taken:    ", $milliseconds, "ms"
            Write-Host "Request Id:    ", $requestId
            Write-Host
            
        }    
        catch {
            Write-Host
            Write-Host "We're unable to complete the AutoDiscover Reuqest for this email adress with following error" -ForegroundColor Red
            Write-Host "---------------------------------------------------------------------------------------------------------------"
            Write-Error $_.Exception.Message
            Write-Host            
        }
    }
}

if($Hybrid) {
    Test-AutoDetect
    Test-EXOAutoDV2
}
elseif($TestEXOAutoDV2){
    Test-EXOAutoDV2
}
elseif ($TestOnPremAutoDV2) {
    Test-OnPremAutoDV2
} 
else {
    Get-FederationProvider
}
