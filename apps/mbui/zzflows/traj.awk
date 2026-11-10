# per scenario: mine y (first M), x; rows
function flush(){ if(sc!=""){ printf "%-11s frames=%d  mine: yRev=%d xRev=%d maxJump=%.1f maxDv=%.1f appear@%s  rows: rev=%d down=%.1f\n", sc, n, yrev, xrev, mj, mdv, app, rrev, rdown } }
{ if($2!=sc){ flush(); sc=$2; n=0; yrev=0; xrev=0; mj=0; mdv=0; app="-"; py=""; px=""; pv=""; pxv=""; delete ry; delete rv; rrev=0; rdown=0 }
  n++; m=""; ri=0
  for(i=4;i<=NF;i++){ if($i ~ /^M:/ && m==""){ m=substr($i,3) } else if($i ~ /^R:/){ ri++; v=substr($i,3); if(v!="-"){ v=v/10; if(ri in ry){ d=v-ry[ri]; if(d>0.05) rdown+=d; if((ri in rv) && rv[ri]*d<0 && (d>0.3||d<-0.3)) rrev++; if(d>0.3||d<-0.3) rv[ri]=d } ry[ri]=v } } }
  if(m!=""){ split(m,a,","); x=a[1]; y=a[2]/10; if(app=="-") app=$3
    if(py!=""){ v=y-py; xv=x-px; if((v>0?v:-v)>mj) mj=(v>0?v:-v); if(pv!=""){ dv=v-pv; if((dv>0?dv:-dv)>mdv) mdv=(dv>0?dv:-dv); if(pv*v<0 && (v>0.3||v<-0.3)) yrev++ } if(pxv!="" && pxv*xv<0 && (xv>1||xv<-1)) xrev++; pv=v; if(xv>1||xv<-1) pxv=xv }
    py=y; px=x } }
END{ flush() }
