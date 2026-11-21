import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
Deno.serve(async (req) => {
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 try {
  const auth=req.headers.get("Authorization")??"";
  const u=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}}});
  const {data:{user},error:ae}=await u.auth.getUser();
  if(ae||!user) return new Response("Unauthorized",{status:401,headers:cors});
  const body=await req.json();
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const {data:ride,error}=await admin.from("ride_requests").select("*").eq("id",body.request_id).eq("passenger_id",user.id).single();
  if(error||!ride) return new Response("Ride request not found",{status:404,headers:cors});
  const {data:drivers}=await admin.from("driver_presence").select("driver_id,latitude,longitude").eq("online",true).eq("vehicle_type",ride.vehicle_type).gt("updated_at",new Date(Date.now()-90000).toISOString());
  const rad=(v:number)=>v*Math.PI/180;
  const ids=(drivers??[]).filter(d=>{const a=rad(ride.pickup_latitude-d.latitude),b=rad(ride.pickup_longitude-d.longitude);const h=Math.sin(a/2)**2+Math.cos(rad(d.latitude))*Math.cos(rad(ride.pickup_latitude))*Math.sin(b/2)**2;return 6371*2*Math.atan2(Math.sqrt(h),Math.sqrt(1-h))<=8;}).map(d=>d.driver_id);
  if(!ids.length) return Response.json({sent:0},{headers:cors});
  const {data:tokens}=await admin.from("driver_push_tokens").select("token").in("user_id",ids);
  const account=JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")??"{}");
  if(!account.project_id||!account.client_email||!account.private_key) return new Response("FCM_SERVICE_ACCOUNT_JSON secret missing",{status:503,headers:cors});
  const key=await importPKCS8(account.private_key,"RS256"), now=Math.floor(Date.now()/1000);
  const assertion=await new SignJWT({scope:"https://www.googleapis.com/auth/firebase.messaging"}).setProtectedHeader({alg:"RS256",typ:"JWT"}).setIssuer(account.client_email).setAudience("https://oauth2.googleapis.com/token").setIssuedAt(now).setExpirationTime(now+3600).sign(key);
  const oauth=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion})});
  const authData=await oauth.json(); if(!oauth.ok) throw new Error("Google OAuth token request failed");
  let sent=0;
  for(const item of tokens??[]){
   const msg={message:{token:item.token,notification:{title:"Tip Car: New ride request",body:"A nearby "+ride.vehicle_type+" taxi request is available."},data:{request_id:ride.id,kind:"instant_ride"}}};
   const response=await fetch("https://fcm.googleapis.com/v1/projects/"+account.project_id+"/messages:send",{method:"POST",headers:{Authorization:"Bearer "+authData.access_token,"content-type":"application/json"},body:JSON.stringify(msg)});
   if(response.ok) sent++;
  }
  return Response.json({sent},{headers:cors});
 } catch(e) { return new Response(String(e?.message??e),{status:500,headers:cors}); }
});
