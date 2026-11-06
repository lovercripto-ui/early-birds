'use strict';
// Recovery sessions belong on the isolated reset page; never display tokens.
if(new URLSearchParams(location.hash.slice(1)).get('type')==='recovery')location.replace(new URL('./recover.html',location.href).href+location.hash);
