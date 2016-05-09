/*
Copyright (C) 2016, Silent Circle, LLC.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Any redistribution, use, or modification is done solely for personal
      benefit and not for any commercial purpose or for monetary gain
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name Silent Circle nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL SILENT CIRCLE, LLC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
//
// /FORCE:MULTIPLE --- sha2 polarssl and libzrtp
//warning LNK4088: image being generated due to /FORCE option; image may not run
#include "CTTLS.h"

#include "../../tiviengine/tivi_log.h"

#define T_ENABLE_TLS

#include <string.h>
#include <stdio.h>

#ifdef T_ENABLE_TLS

#include <polarssl/config.h>
#include <polarssl/net.h>
#include <polarssl/ssl.h>
#include <polarssl/entropy.h>
#include <polarssl/ctr_drbg.h>
#include <polarssl/error.h>

static void * (*volatile memset_volatile)(void *, int, size_t) = memset;

#define DEBUG_LEVEL 2

#ifdef __APPLE__
void relTcpBGSock(void *ptr);
void *prepareTcpSocketForBg(int s);
#else
void relTcpBGSock(void *ptr){}
void *prepareTcpSocketForBg(int s){return (void*)1;}
#endif

int mustCheckTLSCert();

#ifdef _WIN32
#define snprintf _snprintf
#endif

class CTAutoIntUnlock{
   int *iV;
public:
   CTAutoIntUnlock(int *iV):iV(iV){
      *iV=1;
   }
   ~CTAutoIntUnlock(){
      *iV=0;
   }
};



void tivi_slog(const char* format, ...);

void tmp_log(const char *p);

void my_debug( void *ctx, int level, const char *str )
{
   /*
    {
    fprintf( (FILE *) ctx, "%s", str );
    fflush(  (FILE *) ctx  );
    }
    */
   //if( level < DEBUG_LEVEL )
   //tivi_slog("lev[%d]%s",level,str);
}

void *getEncryptedPtr_debug(void *p){
   
   if(!p)return NULL;//dont leak the key
   
   static unsigned long long bufKey;
   static int iInit=1;
   if(iInit){
      iInit=0;
      FILE *f=fopen("/dev/urandom","rb");;
      if(f){
         fread(&bufKey,1,8,f);
         fclose(f);
      }
   }
   unsigned long long ull=(unsigned long long)p;
   
   if(ull<10000)return p;//dont leak the key
   
   ull^=bufKey;
   
   return (void*)ull;
}


typedef struct{
	ssl_session ssn;
	ssl_context ssl;
   //   x509_cert cacert;
   x509_crt cacert;
   
   // pk_context pkey;
   
	entropy_context entropy;
	ctr_drbg_context ctr_drbg;
	int sock;
   void *voipBCKGR;
}T_SSL;

CTTLS::CTTLS(CTSockCB &c):addrConnected(){
	cert=NULL;
   iConnected=0;
   iClosed=1;
   iNeedCallCloseSocket=0;
   iPeerClosed=0;
	pSSL=new T_SSL;
   pRet=NULL;
   errMsg=NULL;
	memset(pSSL,0,sizeof(T_SSL));
   iWaitForRead=0;
   iCertFailed=0;
   iEntropyInicialized=0;
   iCallingConnect=0;
   bIsVoipSock = 0;
   
   
}

void CTTLS::enableBackgroundForVoip(int bTrue){
   bIsVoipSock = bTrue;
}

void CTTLS::initEntropy(){
   if(iEntropyInicialized)return;
   iEntropyInicialized=1;
   int ret;
   char *getEntropyFromZRTP_tmp(unsigned char *p, int iBytes);
   unsigned char br[64];
	
  // unsigned int getTickCount(void);
  // unsigned int ui=getTickCount();
   
	entropy_init( &((T_SSL*)pSSL)->entropy );
	if( ( ret = ctr_drbg_init( &((T_SSL*)pSSL)->ctr_drbg, entropy_func, &((T_SSL*)pSSL)->entropy,
                             (unsigned char *) getEntropyFromZRTP_tmp(&br[0],63), 63 ) ) != 0 )
	{
        t_logf(log_events, __FUNCTION__,"failed! ctr_drbg_init returned %d", ret );
	}
  // printf("[init tls entrpoy sp=%d ms]\n",getTickCount()-ui);
}

CTTLS::~CTTLS(){
   
   closeSocket();
   
   if(iEntropyInicialized)
      entropy_free(&((T_SSL*)pSSL)->entropy);
	memset_volatile(pSSL,0,sizeof(T_SSL));
	delete (T_SSL*)pSSL;
	if(cert)delete cert;
}

int CTTLS::createSock(){
   iPeerClosed=0;
	return 0;
}

int CTTLS::closeSocket(){
   
	if((!iConnected && iPeerClosed==0)  || iClosed){
      if(iNeedCallCloseSocket && pSSL && ((T_SSL*)pSSL)->sock){
         SOCKET server_fd=((T_SSL*)pSSL)->sock;
         net_close(server_fd);
      }
      iNeedCallCloseSocket=0;
      
      return 0;
   }
   addrConnected.clear();
   iPeerClosed=0;
	iConnected=0;
   iClosed=1;
	
	ssl_context *ssl=&((T_SSL*)pSSL)->ssl;
   
	ssl_close_notify( ssl );
   
   Sleep(60);
   
   SOCKET server_fd=((T_SSL*)pSSL)->sock;
   net_close( server_fd );
   
   Sleep(80);
	if(ssl){
      x509_crt_free( &((T_SSL*)pSSL)->cacert );
      ssl_free( ssl );
   }
   //
   
   ((T_SSL*)pSSL)->sock=0;
	
   iNeedCallCloseSocket=0;
	return 0;
}
void CTTLS::setCert(char *p, int iLen, char *pCertBufHost){
   if(cert)delete cert;
   cert=new char[iLen+1];
   if(!cert)return;
   memcpy(cert,p,iLen);
   cert[iLen]=0;
   int l = (int)strlen(pCertBufHost);
   if(l>sizeof(bufCertHost)-1)l=sizeof(bufCertHost)-1;
   strncpy(bufCertHost,pCertBufHost,l);
   bufCertHost[l]=0;
}

static int iLastTLSSOCK_TEST;
void test_close_last_sock(){
   closesocket(iLastTLSSOCK_TEST);
}


/*
 int ctr_drbg_randomx( void *p_rng,
 unsigned char *output, size_t output_len ){
 char *getEntropyFromZRTP_tmp(unsigned char *p, int iBytes);
 
 getEntropyFromZRTP_tmp(output,(int)output_len);
 
 return 0;
 }
 */
typedef struct{
   int idx;
   
   int iSelected;
   
   int iFailed;
   
   int iConnected;
   
   int f;
   
   char host[128];
   int port;
   
   int iCanDelete;
   
}TH_C_TCP;

static int th_connect_tcp(void *p){
   TH_C_TCP *tcp = (TH_C_TCP*)p;
   
   if(!net_connect(&tcp->f, tcp->host, tcp->port)){
      tcp->iConnected = 1;
   }
   else tcp->iFailed = 1;
   
   int iMax = 2000;
   while (!tcp->iCanDelete && iMax>0) {
      Sleep(50);
      iMax--;
   }
   
   if(iMax<2){
      puts("WARN: th_connect_tcp max<2");
   }
   //do not delete this imidiatly
   if(!tcp->iSelected && tcp->iConnected){
      close(tcp->f);
   }
   Sleep(200);
   delete tcp;
   return 0;
}

//return fastet possible connection
static int fast_tcp_connect(ADDR *address, int iIncPort){
#define T_MAX_TCP_ADDR_CNT 8
   
   int ips[T_MAX_TCP_ADDR_CNT];
   
   CTSock::getHostByName(address->bufAddr, 0, (int*)&ips, T_MAX_TCP_ADDR_CNT);

   TH_C_TCP *tcp[T_MAX_TCP_ADDR_CNT];

   for(int i=0;i<T_MAX_TCP_ADDR_CNT;i++){
      if(ips[i]==0)break;
      
      TH_C_TCP *p  = new TH_C_TCP;
      memset(p, 0, sizeof(TH_C_TCP));
      p->idx = i;
      
      ADDR a;
      a.ip = ips[i];
      a.toStr(&p->host[0],0);
      
      p->port = address->getPort()+iIncPort;
      
       printf("[net_connect(addr=%s port=%d); idx=%d]\n", &p->host[0], address->getPort()+iIncPort,i);
      
      void startThX(int (cbFnc)(void *p),void *data);
      startThX(th_connect_tcp, p);
      tcp[i] = p;
   }
   

   int iConnected = -1;
   int iMaxTestsLeft=0;
   
   
   
   while(1){
      Sleep(40);
      int iSocketsDone = 0;
      int iSockets = 0;
      for(int i=0;i<T_MAX_TCP_ADDR_CNT;i++){
         if(ips[i]==0)break;
         iSockets++;
         iSocketsDone += (tcp[i]->iConnected || tcp[i]->iFailed);
         
         if(tcp[i]->iConnected && (iConnected==-1 || i < iConnected)){
            iConnected = i;
            //should we  reset here or we should wait just 3sec
         }
      }
      if(iConnected>=0){
         iMaxTestsLeft++;
         if(iMaxTestsLeft > 25 * 3)break; //wait 3sec after first socket connect
         if(iConnected == 0)break;//noone can be better than first record
      }
      if(iSockets == iSocketsDone)break;
   }
   
   int ret = iConnected==-1 ? 0 : tcp[iConnected]->f;
   if(ret){
      tcp[iConnected]->iSelected = 1;
      t_logf(log_events, __FUNCTION__, "[selected net_connect(addr=%s port=%d); idx=%d]\n", &tcp[iConnected]->host[0], address->getPort()+iIncPort,iConnected);
   }
   
   for(int i=0;i<T_MAX_TCP_ADDR_CNT;i++){
      if(ips[i]==0)break;
      tcp[i]->iCanDelete = 1;
   }
   return ret;
}

int CTTLS::_connect(ADDR *address){
    addrConnected=*address;
    // int server_fd=((T_SSL*)pSSL)->sock;
    ssl_context *ssl=&((T_SSL*)pSSL)->ssl;
    x509_crt *ca=&((T_SSL*)pSSL)->cacert;

#if 0
   const int ssl_default_ciphersuitesz[] =
   {
#if defined(POLARSSL_DHM_C)
#if defined(POLARSSL_AES_C)
#if defined(POLARSSL_SHA2_C)
      TLS_DHE_RSA_WITH_AES_256_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
#if defined(POLARSSL_GCM_C) && defined(POLARSSL_SHA4_C)
      TLS_DHE_RSA_WITH_AES_256_GCM_SHA384,
#endif
      TLS_DHE_RSA_WITH_AES_256_CBC_SHA,
#if defined(POLARSSL_SHA2_C)
      TLS_DHE_RSA_WITH_AES_128_CBC_SHA256,
#endif
#if defined(POLARSSL_GCM_C) && defined(POLARSSL_SHA2_C)
      TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,
#endif
      TLS_DHE_RSA_WITH_AES_128_CBC_SHA,
#endif
#if defined(POLARSSL_CAMELLIA_C)
#if defined(POLARSSL_SHA2_C)
      TLS_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
      TLS_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA,
#if defined(POLARSSL_SHA2_C)
      TLS_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
      TLS_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA,
#endif
#if defined(POLARSSL_DES_C)
      TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA,
#endif
#endif
      
      
#if defined(POLARSSL_AES_C)
#if defined(POLARSSL_SHA2_C)
      TLS_RSA_WITH_AES_256_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
#if defined(POLARSSL_GCM_C) && defined(POLARSSL_SHA4_C)
      TLS_RSA_WITH_AES_256_GCM_SHA384,
#endif /* POLARSSL_SHA2_C */
      TLS_RSA_WITH_AES_256_CBC_SHA,
#endif
#if defined(POLARSSL_CAMELLIA_C)
#if defined(POLARSSL_SHA2_C)
      TLS_RSA_WITH_CAMELLIA_256_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
      TLS_RSA_WITH_CAMELLIA_256_CBC_SHA,
#endif
#if defined(POLARSSL_AES_C)
#if defined(POLARSSL_SHA2_C)
      TLS_RSA_WITH_AES_128_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
#if defined(POLARSSL_GCM_C) && defined(POLARSSL_SHA2_C)
      TLS_RSA_WITH_AES_128_GCM_SHA256,
#endif /* POLARSSL_SHA2_C */
      TLS_RSA_WITH_AES_128_CBC_SHA,
#endif
#if defined(POLARSSL_CAMELLIA_C)
#if defined(POLARSSL_SHA2_C)
      TLS_RSA_WITH_CAMELLIA_128_CBC_SHA256,
#endif /* POLARSSL_SHA2_C */
      TLS_RSA_WITH_CAMELLIA_128_CBC_SHA,
#endif
#if defined(POLARSSL_DES_C)
      TLS_RSA_WITH_3DES_EDE_CBC_SHA,
#endif
#if defined(POLARSSL_ARC4_C)
      //  TLS_RSA_WITH_RC4_128_SHA,
      // TLS_RSA_WITH_RC4_128_MD5,
#endif
      0
   };
#endif
    if(iCallingConnect)return 0;

    CTAutoIntUnlock _a(&iCallingConnect);

    if(!iClosed) {
        closeSocket();
        Sleep(100);
    }

    char bufX[64];
    address->toStr(&bufX[0],0);
    int iIncPort=0;
    if (address->getPort()==5060)iIncPort++;        // TODO fix

   int ret;
    iConnected=0;

   //TODO free

    memset(ca, 0, sizeof( x509_crt ));

    x509_crt_init(ca);
    //  x509_crt_init( &clicert );
    //pk_init( &pkey );

    do {
        int iCertErr=1;
        char *p=cert;
        if(cert){
            iCertErr = x509_crt_parse(ca, (unsigned char *)p, strlen(p));
        }
        if(mustCheckTLSCert() && (!cert || iCertErr)){
            failedCert("No TLS Certificate",NULL,1);
            return -1;
        }

       //we could try to resolve the domain here,
       //but we can not assing that address to the (ADDR address),
       //Reason: CTSipSock will fight and close socket, if we do so we have to update GW.ip and px.ip
       /*
        memset(port_str, 0, sizeof(port_str));
        snprintf(port_str, sizeof(port_str), "%d", host_port);
        
        // Do name resolution with both IPv6 and IPv4, but only TCP
        memset( &hints, 0, sizeof(hints));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_protocol = IPPROTO_TCP;
        
        getaddrinfo(host_ipstr, port_str, &hints, &addr_list);
       // (UInt8*)addr_list->ai_addr,addr_list->ai_addrlen;
        */
#if 1

       ((T_SSL*)pSSL)->sock = fast_tcp_connect(address, iIncPort);

#else
       int ips[8];
       
       CTSock::getHostByName(address->bufAddr, 0, (int*)&ips, 8);
       
       for(int i=0;i<8;i++){
          if(ips[i]==0)break;
          
          ADDR a;
          a.ip = ips[i];
          a.toStr(&bufX[0],0);
          
          t_logf(log_events, __FUNCTION__, "[net_connect(addr=%s port=%d);]", bufX, address->getPort()+iIncPort);
          printf("[net_connect(addr=%s port=%d);]", bufX, address->getPort()+iIncPort);
          
          if(net_connect(&(((T_SSL*)pSSL)->sock), &bufX[0], address->getPort()+iIncPort)){
             ((T_SSL*)pSSL)->sock = 0;
             continue;
          }
          
          break;
       }
#endif
       
       
       if(!((T_SSL*)pSSL)->sock){
          break;
       }

        iLastTLSSOCK_TEST=(((T_SSL*)pSSL)->sock);
        iNeedCallCloseSocket=1;

#ifndef _WIN32
        int on=1;
        /*
         int* delay = X; setsockopt(sockfd,SOL_TCP,TCP_KEEPIDLE,&delay,sizeof(delay)); int count = X; setsockopt(sockfd,SOL_TCP,TCP_KEEPCNT,&count,sizeof(count)); int interval = X; setsockopt(sockfd,SOL_TCP,TCP_KEEPINTVL,&interval,sizeof(interval)); int enable = 1; setsockopt(sockfd,SOL_SOCKET,SO_KEEPALIVE,&enable,sizeof(enable));
         */

        setsockopt((((T_SSL*)pSSL)->sock), SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on));//new 05052012
        //TODO set this if need backgr only
#endif
        relTcpBGSock(((T_SSL*)pSSL)->voipBCKGR);
        if(bIsVoipSock){
           ((T_SSL*)pSSL)->voipBCKGR=prepareTcpSocketForBg(((T_SSL*)pSSL)->sock);//ios sets to non-blocking socket here.
        }
        //make sure to have blocking socket, the iOS defualts to non-blocking for voip
        net_set_block(((T_SSL*)pSSL)->sock);//
       
       

        initEntropy();

        if ((ret = ssl_init( ssl ) ) != 0 ) {
            error_strerror(ret, &bufErr[0], sizeof(bufErr)-1);
            t_logf(log_events, __FUNCTION__, "ssl_init failed: [%s]", &bufErr[0]);
            break;
        }

        ssl_set_endpoint(ssl, SSL_IS_CLIENT);
        ssl_set_authmode( ssl, SSL_VERIFY_REQUIRED );
//       ssl_set_authmode( ssl, iCertErr == 0 ? SSL_VERIFY_REQUIRED: SSL_VERIFY_NONE );

        ssl_set_rng(ssl, ctr_drbg_random, &((T_SSL*)pSSL)->ctr_drbg);
        ssl_set_dbg(ssl, my_debug, stdout);
        ssl_set_bio(ssl, net_recv, (void*)&(((T_SSL*)pSSL)->sock), net_send, (void*)&(((T_SSL*)pSSL)->sock));

        ssl_set_ciphersuites(ssl, ssl_list_ciphersuites());
        //ssl_set_session( ssl, 1, 600, &((T_SSL*)pSSL)->ssn );//will  timeout after 600, and will be resumed
        //ssl_set_session( ssl, 1, 0, &((T_SSL*)pSSL)->ssn );//will never timeout, and will be resumed

        iCertFailed=0;
        if (1|| iCertErr == 0){
            ssl_set_ca_chain( ssl, ca, NULL, &bufCertHost[0] );
            ssl_set_hostname( ssl, &bufCertHost[0] );
            int r = checkCert();
            if(r < 0){
               if(r==-1){//do not show the message if TLS handshake fails. SP-453
                  failedCert("Certificate failed",NULL,1);
               }
               iCertFailed = 1;
               iClosed=0;
               return 0;
            }
        }
        iClosed=0;
        iConnected=1;
        addrConnected=*address;
    } while(0);
    return 0;
}

void CTTLS::failedCert(const  char *err, const char *descr, int fatal){
   if(descr)t_logf(log_events, __FUNCTION__,err,descr);
   else t_logf(log_events, __FUNCTION__, err);
   if(fatal){
      if(errMsg)errMsg(pRet,err);
      iCertFailed=1;
   }
   
}

int CTTLS::getInfo(const char *key, char *p, int iMax){
   if(!pSSL)return 0;
   
   ssl_context *ssl=&((T_SSL*)pSSL)->ssl;
   p[0]=0;
   
   if(!ssl){
      strncpy(p,"SSL is not connected",iMax);
   }else {
      const char *pdst = ssl_get_ciphersuite( ssl );
      if(pdst && strlen(pdst)>4){
         int b = (ssl->dhm_P.n * 8) ;//ssl->dhm_P.n ?
         //:
         //(ssl->rsa_key && ssl->rsa_key_len ? ssl->rsa_key_len( ssl->rsa_key ) : 0);
         
         b*=8;
         
         char *stripText(char *dst, int iMax, const char *src, const char *cmp);
         
         int l = snprintf(p, iMax,"%dbits ", b);
         stripText(p+l, iMax-l-1, pdst+4, "-WITH");
      }
   }
   return strlen(p);
}

int CTTLS::checkCert(){
   int ret;

   ssl_context *ssl=&((T_SSL*)pSSL)->ssl;
   log_events( __FUNCTION__, "Starting TLS handshake..." );
 
   while ((ret = ssl_handshake(ssl)) != 0)
   {
      if( ret != POLARSSL_ERR_NET_WANT_READ && ret != POLARSSL_ERR_NET_WANT_WRITE )
      {
          char buffer[1000];
          polarssl_strerror(ret, buffer, 1000);
          t_logf(log_events, __FUNCTION__, "FAIL! ssl_handshake returned %x, Message: %s", ret, buffer);

         return -2;
      }
#ifndef _WIN32
      usleep(20);
#else
      Sleep(15);
#endif
   }
   t_logf(log_events, __FUNCTION__, "OK [Ciphersuite is %s]", ssl_get_ciphersuite( ssl ) );
   /*
    * 5. Verify the server certificate
    */
   t_logf(log_events, __FUNCTION__, "Verifying peer X.509 certificate...");
   
   if (( ret = ssl_get_verify_result( ssl ) ) != 0 ) {

      t_logf(log_events, __FUNCTION__, "Fail: ssl_get_verify_result()=%d",ret);
      
      // ssl_context *ssl2=&((T_SSL*)pSSL)->ssl;
      //  puts((char*)ssl2->ca_chain->subject.val.p);
      
      if( ( ret & BADCERT_EXPIRED ) != 0 )
         failedCert( "  ! server certificate has expired",NULL,1 );
      
      if( ( ret & BADCERT_REVOKED ) != 0 )
         failedCert( "  ! server certificate has been revoked",NULL,1 );
      
      if( ( ret & BADCERT_CN_MISMATCH ) != 0 ){
         failedCert( "  ! CN mismatch (expected CN=%s)",this->bufCertHost,1);
      }
      
      if( ( ret & BADCERT_NOT_TRUSTED ) != 0 )
         failedCert( "  ! self-signed or not signed by a trusted CA",NULL,1 );
      
      return -1;
      
   }
   else
     log_events(__FUNCTION__,"OK");
   /* failed!
    tivi_slog( "  . Peer certificate information    ..." );
    x509parse_cert_info( (char *) buf, sizeof( buf ) - 1, "      ", ssl->peer_cert );
    tivi_slog( "%s", buf );*/
   return 0;
}


int CTTLS::_send(const char *buf, int iLen){
    ssl_context *ssl=&((T_SSL*)pSSL)->ssl;
    if(!iConnected)return -1001;
    if(iClosed)return -1002;
    if(iCertFailed){Sleep(30);return -1003;}

    int ret=0;
    int iShouldDisconnect=0;
    while((ret = ssl_write( ssl, (const unsigned char *)buf, iLen ) ) <= 0 )
    {
        sleep(20);

        if (ret != POLARSSL_ERR_NET_WANT_READ && ret != POLARSSL_ERR_NET_WANT_WRITE ) {
            iShouldDisconnect=1;
            Sleep(5);
            break;
        }
        if(!iConnected)break;

        if(ret == POLARSSL_ERR_NET_WANT_READ){
            iWaitForRead=1;
            for(int i=0;i<5 && iWaitForRead;i++)
                Sleep(20);
        }
    }
    // Use this if we need a SIP trace: tivi_slog("[ssl-send=%p %.*s l=%d ret=%d]", getEncryptedPtr_debug(ssl), 800, buf, iLen, ret);
    // On Android max log line length is about 1K
    t_logf(log_events, __FUNCTION__, "[ssl-send=%p %.*s l=%d ret=%d]", getEncryptedPtr_debug(ssl), 12, buf, iLen, ret);

    if (ret < 0) {
        if(ret==POLARSSL_ERR_NET_CONN_RESET || ret==POLARSSL_ERR_NET_SEND_FAILED){
            iShouldDisconnect=1;
        }
        if(iShouldDisconnect){addrConnected.clear();iConnected=0; log_events(__FUNCTION__, "tls_send err clear connaddr");}
        error_strerror(ret, bufErr, sizeof(bufErr)-1);
        t_logf(log_events, __FUNCTION__, "send[%s] %d", bufErr, iShouldDisconnect);
    }
    else {
        //TODO msg("getCS",5,void *p, int iSize);
        //  tivi_slog( " [ Ciphersuite is %s ]\n", ssl_get_ciphersuite( ssl ) );
    }

    return ret;
}
int CTTLS::_recv(char *buf, int iMaxSize){
	
	int ret=0;
	ssl_context *ssl=&((T_SSL*)pSSL)->ssl;
   if(iCertFailed){Sleep(30);return 0;}
   if(!isConected()){Sleep(iPrevReadRet==100000?30:15);iPrevReadRet=100000;return -1;}
   
   int iPOLARSSL_ERR_NET_WANT_cnt=0;
   
	while(!iClosed){
      //  puts("read sock");
      iWaitForRead=0;
	   ret = ssl_read( ssl, (unsigned char *)buf, iMaxSize );
      //   void wakeCallback(int iLock);wakeCallback(1);
      
      
      if(!iConnected)break;
      
      if( ret == POLARSSL_ERR_NET_WANT_READ || ret == POLARSSL_ERR_NET_WANT_WRITE ){
         
         Sleep(ret == POLARSSL_ERR_NET_WANT_WRITE?50:5);
         if(iPrevReadRet==ret)
            Sleep(50);
         iPOLARSSL_ERR_NET_WANT_cnt++;
         
         if(iPOLARSSL_ERR_NET_WANT_cnt<20)printf("[sock rw]");
         iPrevReadRet=ret;
         continue;
         //break;
      }
      if( ret == POLARSSL_ERR_SSL_PEER_CLOSE_NOTIFY || ret == 0){
         iConnected=0;
         iPeerClosed=2;
         Sleep(10);
         break;
      }
      
      if( ret < 0 )
      {
         t_logf(log_events, __FUNCTION__, "failed  ! ssl_read returned %d", ret );
         break;
      }
      
      break;
   };
   if(iPeerClosed==2 || ret==POLARSSL_ERR_NET_CONN_RESET || ret==POLARSSL_ERR_NET_RECV_FAILED){
      t_logf(log_events, __FUNCTION__, "tls_recv err clear connaddr ret=%d pc=%d",ret, iPeerClosed);
      iPeerClosed=1;
      this->addrConnected.clear();
      iConnected=0;
      
   }
   else{
       // Use this if we need a SIP trace: tivi_slog("[ssl-recv=%p %.*s max=%d ret=%d]", getEncryptedPtr_debug(ssl), 800, buf, iMaxSize, ret);
    // On Android max log line length is about 1K
      if(ret>=0)
        t_logf(log_events, __FUNCTION__,"[ssl-recv=%p %.*s max=%d ret=%d]", getEncryptedPtr_debug(ssl), 50<ret?50:ret, buf, iMaxSize, ret);
   }
   
   if(ret<0){
      error_strerror(ret,&bufErr[0],sizeof(bufErr)-1);
      t_logf(log_events, __FUNCTION__,"<<<rec[%s]pc[%d]",&bufErr[0],iPeerClosed);
   }
   
   
   if(ret<=0 && iPrevReadRet==ret){
      Sleep(ret==iPPrevReadRet?100:50);
   }
   iPPrevReadRet=iPrevReadRet;
   iPrevReadRet=ret;
   
   return ret;
}

void CTTLS::reCreate(){
	//closeSocket();
	//createSock();
}
#else
CTTLS::CTTLS(CTSockCB &c){}
CTTLS::~CTTLS(){}
void CTTLS::reCreate(){}
int CTTLS::createSock(){return 0;}
int CTTLS::closeSocket(){return 0;}
int CTTLS::_connect(ADDR *address){return 0;}
int CTTLS::_send(const char *buf, int iLen){return 0;}
int CTTLS::_recv(char *buf, int iLen){return 0;}
void CTTLS::setCert(char *p, int iLen, char *host){}
void CTTLS::failedCert(const char *err, const char *descr, int fatal){}
int CTTLS::checkCert(){return 0;}
#endif

/*
 int t_recvTLS(void *pSock, char *buf, int len){
 int ret=0;
 T_SSL *s=(T_SSL*)pSock;
 
 do
 {
 memset( buf, 0, len);
 ret = ssl_read( &s->ssl, (unsigned char*)buf, len );
 
 if( ret == POLARSSL_ERR_NET_WANT_READ || ret == POLARSSL_ERR_NET_WANT_WRITE )
 continue;
 
 
 if( ret <= 0 )
 {
 switch( ret )
 {
 case POLARSSL_ERR_SSL_PEER_CLOSE_NOTIFY:
 DEBUG_TLS(0, " connection was closed gracefully\n" );
 s->iNeedClose=1;
 break;
 
 case POLARSSL_ERR_NET_CONN_RESET:
 DEBUG_TLS(0, " connection was reset by peer\n" );
 s->iNeedClose=1;
 break;
 
 default:
 DEBUG_RET( " ssl_read returned %d\n", ret );
 s->iNeedClose=2;
 break;
 }
 
 break;
 }
 
 
 
 // printf( " %d bytes read\n\n%s", len, (char *) buf );
 }
 while( 0 );
 
 return ret;
 }
 
 */

//   ADDR addr;

