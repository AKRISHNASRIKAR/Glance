#!/usr/bin/env python3
"""Generate static discovery metadata. No deployment or remote writes."""
from pathlib import Path
from html import escape
import json,re
ROOT=Path(__file__).resolve().parent.parent
SITE=ROOT/'frontend'
ORIGIN='https://glance-notch.vercel.app'
PAGES={
 '/':('Glance | Your MacBook notch, with a purpose','Music, Pomodoro and optional context in your MacBook notch. Explore Glance for Mac and its local-first Chrome focus companion.','social-glance.png',True),
 '/extension/':('Glance Focus | Website blocking for Chrome','Block distracting websites during Pomodoro. Pair with Glance on Mac for a shared timer, or use Chrome on its own. No account required.','social-extension.png',True),
 '/extension/connect/':('Connect Chrome to Glance for Mac | Setup guide','Set up the Glance Focus developer preview, approve local Mac pairing, and troubleshoot the browser connection.','social-extension.png',True),
 '/icon-lab.html':('Icon studies | Glance','Explore Glance icon motion studies with play, pause and reduced-motion controls.','social-glance.png',True),
 '/extension/dashboard/':('Local focus dashboard | Glance','Manage your local Glance Focus timer, website list, Mac connection and optional activity. Open from the Chrome extension.','social-extension.png',False),
}
def generate():
 for route,(title,description,preview,index) in PAGES.items():
  file=SITE/(route.lstrip('/') if route.endswith('.html') else route.lstrip('/')+'index.html')
  text=file.read_text()
  text=re.sub(r'\s*<!-- BEGIN GENERATED DISCOVERY -->.*?<!-- END GENERATED DISCOVERY -->\s*','',text,flags=re.S)
  text=re.sub(r'<title>.*?</title>',f'<title>{escape(title)}</title>',text,flags=re.S)
  text=re.sub(r'<meta\s+name=["\']description["\'][^>]*>',f'<meta name="description" content="{escape(description,quote=True)}">',text,flags=re.I)
  url=ORIGIN+route
  graph=[{'@type':'WebSite','@id':ORIGIN+'/#website','url':ORIGIN+'/','name':'Glance','inLanguage':'en'},
   {'@type':'WebPage','@id':url+'#webpage','url':url,'name':title,'description':description,'isPartOf':{'@id':ORIGIN+'/#website'}}]
  if route=='/':graph.append({'@type':'SoftwareApplication','name':'Glance','url':url,'operatingSystem':'macOS','applicationCategory':'ProductivityApplication','description':description,'license':'https://github.com/AKRISHNASRIKAR/Glance/blob/main/LICENSE'})
  if route.startswith('/extension/') and index:
   crumbs=[('Glance','/'),('Glance Focus','/extension/')]
   if route=='/extension/connect/':crumbs.append(('Connect your Mac',route))
   graph.append({'@type':'BreadcrumbList','itemListElement':[{'@type':'ListItem','position':i,'name':name,'item':ORIGIN+path} for i,(name,path) in enumerate(crumbs,1)]})
  tags=[f'<link rel="canonical" href="{url}">',f'<meta name="robots" content="{"index, follow" if index else "noindex, follow"}">']
  for prop,value in [('og:type','website'),('og:site_name','Glance'),('og:locale','en_US'),('og:url',url),('og:title',title),('og:description',description),('og:image',ORIGIN+'/assets/'+preview),('og:image:width','1200'),('og:image:height','630'),('og:image:alt','Glance product preview')]:tags.append(f'<meta property="{prop}" content="{escape(value,quote=True)}">')
  for name,value in [('twitter:card','summary_large_image'),('twitter:title',title),('twitter:description',description),('twitter:image',ORIGIN+'/assets/'+preview)]:tags.append(f'<meta name="{name}" content="{escape(value,quote=True)}">')
  tags.append('<script type="application/ld+json">'+json.dumps({'@context':'https://schema.org','@graph':graph},ensure_ascii=False).replace('<','\\u003c')+'</script>')
  if 'href="/grain.css"' not in text:tags.append('<link rel="stylesheet" href="/grain.css">')
  text=text.replace('</head>','\n<!-- BEGIN GENERATED DISCOVERY -->\n'+'\n'.join(tags)+'\n<!-- END GENERATED DISCOVERY -->\n</head>')
  file.write_text(text)
 (SITE/'robots.txt').write_text(f'User-agent: *\nAllow: /\n\nSitemap: {ORIGIN}/sitemap.xml\n')
 (SITE/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'+''.join(f'  <url><loc>{ORIGIN}{route}</loc></url>\n' for route,data in PAGES.items() if data[3])+'</urlset>\n')
 repo='https://github.com/AKRISHNASRIKAR/Glance'
 short=f'''# Glance

> An open-source macOS notch app with music controls, Pomodoro and optional context. Glance Focus is its local-first Chrome companion.

## Product pages
- [Glance for Mac]({ORIGIN}/): Main app, interactive MacBook demonstration and downloads.
- [Glance Focus]({ORIGIN}/extension/): Website blocking, optional usage stats and standalone focus timer.
- [Connection guide]({ORIGIN}/extension/connect/): Developer preview installation, native pairing and troubleshooting.

## Source and policies
- [Source repository]({repo}): MIT-licensed Swift macOS app, static website and Chrome extension in one repository.
- [Privacy]({repo}/blob/main/docs/PRIVACY.md): Local storage, optional tracking, permissions and network traffic.
- [Extension architecture]({repo}/blob/main/docs/BROWSER_EXTENSION.md): Timer ownership, bridge and testing.
- [Security reporting]({repo}/blob/main/SECURITY.md): Private vulnerability reporting instructions.

## Status and boundaries
The extension is a developer preview, not a published Chrome Web Store listing. It needs no account. When paired, the Mac owns the timer and shared settings. Without the app, a standalone browser timer is available. The hosted dashboard requires explicit authorization from the extension; it is not a cloud account or backend. Website usage tracking is optional and domain-level; activity is retained locally for 30 days. There is no activity upload service. Marketing screenshots are labelled captures or demonstrations, not live user data.
'''
 (SITE/'llms.txt').write_text(short)
 (SITE/'llms-full.txt').write_text(short+'\n## More detail\n\n'+(ROOT/'docs/BROWSER_EXTENSION.md').read_text())
 print('Generated metadata for',len(PAGES),'pages, sitemap, robots and LLM guides.')
if __name__=='__main__':generate()
