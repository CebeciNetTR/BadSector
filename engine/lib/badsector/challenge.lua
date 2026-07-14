--[[
  Challenge issuer — JS, cookie, and captcha challenges.
]]

local util = require("badsector.util")

local _M = {}

--- Issue a challenge to the client.
---@param ctx table RequestContext
---@param challenge_type string
---@param opts table
function _M.issue(ctx, challenge_type, opts)
    opts = opts or {}

    if challenge_type == "js" then
        -- Imzali Proof-of-Work challenge (js_challenge modulu token + difficulty saglar).
        local token = opts.token
        local difficulty = tonumber(opts.difficulty) or 4
        local pow_cookie = opts.pow_cookie or "bs_pow"
        if type(token) ~= "string" or token == "" then
            ngx.log(ngx.ERR, "badsector challenge: js PoW token eksik")
            ngx.status = 403
            return ngx.exit(403)
        end
        ngx.header["Content-Type"] = "text/html; charset=utf-8"
        ngx.header["Cache-Control"] = "no-store"
        ngx.status = 200
        ngx.say(_M.js_challenge_page(token, difficulty, pow_cookie))
        return ngx.exit(200)

    elseif challenge_type == "cookie" then
        local cookie_name = opts.cookie_name or "bs_verified"
        local ttl = tonumber(opts.cookie_ttl) or 86400
        local token = util.random_token(16)
        ngx.header["Set-Cookie"] = cookie_name .. "=" .. token .. "; Path=/; Max-Age=" .. ttl .. "; HttpOnly; SameSite=Lax"
        ngx.header["Cache-Control"] = "no-store"
        ngx.status = 403
        ngx.say("Verification required. Reload to continue.")
        return ngx.exit(403)

    elseif challenge_type == "captcha" then
        ngx.status = 403
        ngx.say("Captcha challenge — configure provider in site settings")
        return ngx.exit(403)
    end

    ngx.status = 403
    return ngx.exit(403)
end

--- Imzali Proof-of-Work challenge sayfasi.
--- Tarayici, senkron SHA-256 ile token'i cozer (parcali dongu -> UI donmaz),
--- cozumu bs_pow cookie'sine yazip sayfayi yeniler. PoW maliyetini istemci oder;
--- sunucu yalnizca 1 hash ile dogrular.
---@param token string   Imzali challenge token (ts.d.salt.sig)
---@param difficulty number  Basta beklenen sifir (hex nibble) sayisi
---@param pow_cookie string   Cozum cookie adi (bs_pow)
---@return string
function _M.js_challenge_page(token, difficulty, pow_cookie)
    return string.format([[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Check | BadSector</title>
    <style>
        body {
            background-color: #0f172a;
            color: #f8fafc;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            overflow: hidden;
        }
        .container {
            text-align: center;
            max-width: 450px;
            padding: 40px;
            background: rgba(30, 41, 59, 0.7);
            border-radius: 16px;
            box-shadow: 0 4px 30px rgba(0, 0, 0, 0.4);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        h1 { font-size: 24px; margin-bottom: 12px; font-weight: 600; }
        p { color: #94a3b8; font-size: 15px; line-height: 1.5; margin-bottom: 24px; }
        .spinner {
            width: 48px; height: 48px;
            border: 4px solid rgba(255, 255, 255, 0.1);
            border-left-color: #3b82f6;
            border-radius: 50%%;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px auto;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        noscript { color: #f87171; }
    </style>
</head>
<body>
    <div class="container">
        <div class="spinner"></div>
        <h1>Checking your browser</h1>
        <p>Verifying your connection before continuing. This is automatic and helps block malicious traffic.</p>
        <noscript>JavaScript is required to continue.</noscript>
    </div>
    <script>
    (function(){
        // Kompakt senkron SHA-256 (public domain, geraintluff) — hex dondurur.
        function sha256(ascii){
            function rr(v,a){return (v>>>a)|(v<<(32-a));}
            var mp=Math.pow, mw=mp(2,32), res='';
            var words=[], bl=ascii.length*8;
            var h=sha256.h=sha256.h||[], k=sha256.k=sha256.k||[];
            var pc=k.length, comp={};
            for(var c=2; pc<64; c++){
                if(!comp[c]){
                    for(var i=0;i<313;i+=c){comp[i]=c;}
                    h[pc]=(mp(c,0.5)*mw)|0;
                    k[pc++]=(mp(c,1/3)*mw)|0;
                }
            }
            ascii+='\x80';
            while(ascii.length%%64-56) ascii+='\x00';
            for(var i=0;i<ascii.length;i++){
                var j=ascii.charCodeAt(i);
                if(j>>8) return;
                words[i>>2]|=j<<((3-i)%%4)*8;
            }
            words[words.length]=(bl/mw)|0;
            words[words.length]=bl;
            for(var j=0;j<words.length;){
                var w=words.slice(j,j+=16), oh=h;
                h=h.slice(0,8);
                for(var i=0;i<64;i++){
                    var w15=w[i-15], w2=w[i-2];
                    var a=h[0], e=h[4];
                    var t1=h[7]
                        +(rr(e,6)^rr(e,11)^rr(e,25))
                        +((e&h[5])^((~e)&h[6]))
                        +k[i]
                        +(w[i]=i<16?w[i]:(
                            w[i-16]
                            +(rr(w15,7)^rr(w15,18)^(w15>>>3))
                            +w[i-7]
                            +(rr(w2,17)^rr(w2,19)^(w2>>>10))
                          )|0);
                    var t2=(rr(a,2)^rr(a,13)^rr(a,22))
                        +((a&h[1])^(a&h[2])^(h[1]&h[2]));
                    h=[(t1+t2)|0].concat(h);
                    h[4]=(h[4]+t1)|0;
                }
                for(var i=0;i<8;i++){h[i]=(h[i]+oh[i])|0;}
            }
            for(var i=0;i<8;i++){
                for(var j=3;j+1;j--){
                    var b=(h[i]>>(j*8))&255;
                    res+=((b<16)?0:'')+b.toString(16);
                }
            }
            return res;
        }
        var TOKEN=%q, DIFF=%d, COOKIE=%q;
        var PREFIX=new Array(DIFF+1).join('0');
        var nonce=0;
        function step(){
            var end=nonce+2000;
            for(; nonce<end; nonce++){
                if(sha256(TOKEN+':'+nonce).slice(0,DIFF)===PREFIX){
                    document.cookie=COOKIE+'='+TOKEN+':'+nonce+';path=/;max-age=300;SameSite=Lax';
                    location.reload();
                    return;
                }
            }
            setTimeout(step,0);
        }
        step();
    })();
    </script>
</body>
</html>]], token, difficulty, pow_cookie)
end

return _M
