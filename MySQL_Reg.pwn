// MySQL Regisztr�ci� rendszer by kurta999
// Verzi�: 3.0
// Last Update: 2014.03.09

#include <a_samp>
#include <a_mysql> // http://forum.sa-mp.com/showthread.php?t=56564
#include <zcmd> // http://forum.sa-mp.com/showthread.php?t=91354

// Ha �reg verzi�j� az a_mysql.inc-je, akkor ki�rjuk neki hogy friss�tsen
#if !defined cache_get_query_exec_time
	#error "Friss�tsd a MySQL (a_mysql.inc) f�ggv�nyk�nyvt�rad az R38-ra, vagy �jabbra!"
#endif


#define             NINCS_REG_CSILLAG // Rakd a kommentt�rba, ha a jelsz�t a j�t�kosnak a regisztr�ci� dial�gusban csillagozni akarod.

// MySQL Debug m�d enged�lyez�s/tilt�sa
//#define MYSQL_DEBUG

#if !defined MYSQL_DEBUG
	#define MYSQL_DEBUG_ 			LOG_ERROR | LOG_WARNING
#else
	#define MYSQL_DEBUG_ 			LOG_ERROR | LOG_WARNING | LOG_DEBUG
#endif

#define ChangeNameDialog(%1) \
    ShowPlayerDialog(%1, DIALOG_CHANGENAME, DIALOG_STYLE_INPUT, !"{" #XCOLOR_RED "}N�vv�lt�s", !"{" #XCOLOR_GREEN "}Lentre �rd be az �j neved! \nHa r�g�ta j�tszol m�r, akkor a n�vv�lt�s t�bb m�sodpercig is eltarthat!\n\n{" #XCOLOR_RED "}Ahogy megv�ltoztattad, r�gt�n v�ltoztasd meg a neved a SAMP-ba!", !"V�ltoztat�s", !"M�gse")

// SendClientMessagef be�gyaz�sa
new g_szFormatString[144];
#define SendClientMessagef(%1,%2,%3) \
    SendClientMessage(%1, %2, (format(g_szFormatString, sizeof(g_szFormatString), %3), g_szFormatString))

// gpci be�gyaz�sa
#if !defined gpci
native gpci(playerid, const serial[], maxlen);
#endif

new
	year,
	month,
	day,
	hour,
	minute,
	second;

new // Direkt adok hozz� + 1 karaktert, mivel valahol a \0 karaktert is t�rolni kell. (Ez 4 karakter, de kell az 5. is, mivel ott t�rolja a \0-t! ['a', 'n', 'y', '�', 'd', '\0'])
	g_szQuery[512 +1],
	g_szDialogFormat[4096],
 	g_szIP[16 +1];

// Bit flagok
enum e_PLAYER_FLAGS (<<= 1)
{
	e_LOGGED_IN = 1,
	e_FIRST_SPAWN
}
new
	e_PLAYER_FLAGS:g_PlayerFlags[MAX_PLAYERS char];

new
	g_pQueryQueue[MAX_PLAYERS];

// MySQL be�ll�t�sok, alapb�l ezek azok a wamp-n�l, csak a t�bla nev�t m�dos�tsd arra, amilyen n�ven l�trehoztad, nekem itt a 'samp'
#define MYSQL_HOST 				"localhost"
#define MYSQL_USER 				"root"
#define MYSQL_PASS 				""
#define MYSQL_DB   				"samp"

// �zenet, amit akkor �r ki, ha a lek�rdez�s befejez�se el�tt lel�p a j�t�kos
#define QUERY_COLLISION(%0) \
	printf("Query collision \" #%0 \"! PlayerID: %d, queue: %d, g_pQueryQueue: %d", playerid, queue, g_pQueryQueue[playerid])

// RRGGBBAA
#define COLOR_GREEN 			0x33FF33AA
#define COLOR_RED				0xFF0000AA
#define COLOR_YELLOW			0xFF9900AA
#define COLOR_PINK 				0xFF66FFAA

// RRGGBB
#define XCOLOR_GREEN 			33FF33
#define XCOLOR_RED 				FF0000
#define XCOLOR_BLUE				33CCFF
#define XCOLOR_YELLOW			FF9900
#define XCOLOR_WHITE			FFFFFF

// Dial�g ID
enum
{
	DIALOG_LOGIN = 20000,
	DIALOG_REGISTER,
	DIALOG_CHANGENAME,
	DIALOG_CHANGEPASS,
	DIALOG_FINDPLAYER
}

// isnull by Y_Less
#define isnull(%1) \
	((!(%1[0])) || (((%1[0]) == '\1') && (!(%1[1]))))

public OnFilterScriptInit()
{
	// MySQL
	print("<< MySQL >> Kapcsol�d�s a(z) " MYSQL_HOST ", " MYSQL_USER " adatb�zis " MYSQL_DB "!");
	mysql_log(MYSQL_DEBUG_);
	mysql_connect(!MYSQL_HOST, !MYSQL_USER, !MYSQL_DB, !MYSQL_PASS);

	if(mysql_errno())
	{
		print("<< MySQL >> Kapcsol�d�s sikertelen! A m�d bez�rul..");
		SendRconCommand(!"exit");
		return 1;
	}

	print("<< MySQL >> Kapcsol�d�s a(z) " MYSQL_HOST " sikeres!");
	print("<< MySQL >> Adatb�zis " MYSQL_DB " kiv�lasztva.\n");
  	return 1;
}

public OnFilterScriptExit()
{
	mysql_close(); // Kapcsolat bont�sa
	return 1;
}

public OnPlayerConnect(playerid)
{
	SetPlayerColor(playerid, (random(0xFFFFFF) << 8) | 0xFF); // GetPlayerColor() jav�t�sa
	g_pQueryQueue[playerid]++;
	
	format(g_szQuery, sizeof(g_szQuery), "SELECT `reg_id` FROM `players` WHERE `name` = '%s'", pName(playerid));
	mysql_pquery(1, g_szQuery, "THREAD_OnPlayerConnect", "dd", playerid, g_pQueryQueue[playerid]);
	return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
	g_pQueryQueue[playerid]++;
	return SavePlayer(playerid, GetPVarInt(playerid, "RegID"));
}

forward THREAD_OnPlayerConnect(playerid, queue);
public THREAD_OnPlayerConnect(playerid, queue)
{
	// Ha a j�t�kos csatlakozik vagy lel�p, akkor a "g_pQueryQueue[playerid]" �rt�ke mindig n�vekedik.
	// Lek�rdez�sn�l �tvissz�k ennek az �rt�k�t a "queue" nev� param�terben, amit majd a lek�rdez�s lefut�s�n�l ellen�rz�nk.
	// Ha a j�t�kos lel�pett, akkor "g_pQueryQueue[playerid]" egyel t�bb lett, teh�t nem egyenl� a "queue" param�ter �rt�k�vel.
	// Ez esetben a lek�rdez�s nem fog lefutni, hanem egy figyelmezet� �zenetet fog ki�rni a konzolva, hogy "query collision".
	// Nagyon fontos ez, mivel ha van egy lek�rdez�s, ami lek�rdez valami "titkos" adatot az adatb�zisb�l,
	// k�zben belaggol a a mysql szerver, a lek�rdez�s eltart 5 m�sodpercig, felj�n egy m�sik j�t�kos �s annak fogja ki�rni az adatokat,
	// mivel a lek�rdez�s lefut�sa k�zben lel�pett a j�t�kos �s egy m�sik j�tt a hely�re. Erre van ez a v�delem, �gy ett�l egy�ltal�n nem kell tartani.
	// Sima lek�rdez�sekn�l (h�z bet�lt�s, egy�b bet�lt�s, friss�t�s, stb.. szars�gok) ilyen helyen nem sz�ks�ges ez a v�delem.
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_OnPlayerConnect);

	new
		szFetch[12],
		serial[64];
	cache_get_row(0, 0, szFetch); 
	SetPVarInt(playerid, "LineID", strval(szFetch));
	// Ez itt egy "�tmeneti v�ltoz�", ami t�rolja, hogy mi a reg id-je a j�t�kosnak.
	// Ha nulla, akkor nincs regisztr�lva (mivel az SQL 0-t ad vissza, ha neml�tez� a sor), ellent�tben pedig igen.
	
	g_PlayerFlags{playerid} = e_PLAYER_FLAGS:0; // Null�zuk az �rt�k�t, nem el�g a nulla, kell el� a v�ltoz� tagja is, k�l�nben figyelmeztet a ford�t�.
    if(!IsPlayerNPC(playerid)) // Csak j�t�kosokra vonatkozik
	{
		SetPVarInt(playerid, "RegID", -1);

		GetPlayerIp(playerid, g_szIP, sizeof(g_szIP));
		gpci(playerid, serial, sizeof(serial));

		getdate(year, month, day);
		gettime(hour, minute, second);

		format(g_szQuery, sizeof(g_szQuery), "INSERT INTO `connections`(id, name, ip, serial, time) VALUES(0, '%s', '%s', '%s', '%02d.%02d.%02d/%02d.%02d.%02d')", pName(playerid), g_szIP, serial, year, month, day, hour, minute, second);
		mysql_pquery(1, g_szQuery);

		// Autologin
		
		// Leftuttatunk egy lek�rdez�st, ami ha befejez�d�tt, akkor megh�v�dik a "THREAD_Autologin" callback.
		// A r�gebbi pluginnal ez egy funkci�ban ment, sz�val ha a mysql szerver belaggolt �s a lek�rdez�s eltartott 5 m�sodpercig,
		// akkor 5 m�sodpercig megfagyott a szerver.
		// Itt nem fog megfagyni semeddig a szerver, mivel l�trehoz neki egy �j sz�lat, �s az a sz�l fagy meg m�g nem fut le a lek�rdez�s.
		// Lefut�s ut�n pedig megh�vja a "THREAD_Autologin" callbackot. Ez m�r logikus, hogy az alap sz�lon (main thread)-on fut.
		//
		// Fenti lek�rdez�ssel is szint�n ez a helyzet, viszont ott nem vagyunk kiv�ncsi a kapott �rt�kekre.
		// Az a lefut�sa sor�n az "OnQueryFinish" callbackot h�vja meg, viszont itt nem t�rt�nik semmi.
		// Ugyanaz a helyzet az �sszes lek�rdez�ssel, ha kiv�ncsi lenn�k az �rt�k�re, akkor ugyan�gy a callback al� rakn�m a dolgokat, mint itt.
		format(g_szQuery, sizeof(g_szQuery), "SELECT * FROM `players` WHERE `name` = '%s' AND `ip` = '%s'", pName(playerid), g_szIP);
		mysql_pquery(1, g_szQuery, "THREAD_Autologin", "dd", playerid, g_pQueryQueue[playerid]);
	}
  	return 1;
}

forward THREAD_Autologin(playerid, queue);
public THREAD_Autologin(playerid, queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Autologin);

	new
	    rows,
	    fields;
	cache_get_data(rows, fields);
	if(rows) // Ha a sor nem �res
	{
		LoginPlayer(playerid);
		SendClientMessage(playerid, COLOR_GREEN, "Automatikusan bejelentkezt�l!");
	}
	return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
	if(IsPlayerNPC(playerid)) return 1;
    
    //printf("%d", g_PlayerFlags{playerid} & e_LOGGED_IN);
	if(!(g_PlayerFlags{playerid} & e_LOGGED_IN)) // Felmutatjuk neki a megfelel� dial�got
	{
		if(GetPVarInt(playerid, "LineID"))
		{
			LoginDialog(playerid);
		}
		else
		{
			RegisterDialog(playerid);
		}
	}
	return 1;
}

public OnPlayerRequestSpawn(playerid)
{
	if(IsPlayerNPC(playerid)) return 1;

	if(!(g_PlayerFlags{playerid} & e_LOGGED_IN)) // Felmutatjuk neki a megfelel� dial�got
	{
		if(GetPVarInt(playerid, "LineID"))
		{
			LoginDialog(playerid);
		}
		else
		{
			RegisterDialog(playerid);
		}
	}
	return 1;
}

public OnPlayerSpawn(playerid)
{
	// Ha el�sz�r spawnol, akkor odaadjuk neki a p�nzt. Mivel skinv�laszt�sn�l nem lehet p�nzt adni a j�t�kosnak!
	if(!(g_PlayerFlags{playerid} & e_FIRST_SPAWN))
	{
		ResetPlayerMoney(playerid);
		GivePlayerMoney(playerid, GetPVarInt(playerid, "Cash"));
		DeletePVar(playerid, "Cash");

		g_PlayerFlags{playerid} |= e_FIRST_SPAWN;
	}

	// �t�sst�lus be�ll�t�sa
	SetPlayerFightingStyle(playerid, GetPVarInt(playerid, "Style"));
	return 1;
}


// Y_Less
NameCheck(const aname[])
{
    new
        i,
        ch;
    while ((ch = aname[i++]) && ((ch == ']') || (ch == '[') || (ch == '(') || (ch == ')') || (ch == '_') || (ch == '$') || (ch == '@') || (ch == '.') || (ch == '=') || ('0' <= ch <= '9') || ((ch |= 0x20) && ('a' <= ch <= 'z')))) {}
    return !ch;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch(dialogid)
	{
		case DIALOG_LOGIN:
		{
			if(!response)
			    return LoginDialog(playerid);

			if(g_PlayerFlags{playerid} & e_LOGGED_IN)
			{
				SendClientMessage(playerid, COLOR_RED, "M�r be vagy jelentkezve.");
				return 1;
			}

			if(isnull(inputtext))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem �rt�l be semilyen jelsz�t!");
				LoginDialog(playerid);
				return 1;
			}

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Rossz jelsz� hossz�s�g! 3 - 20");
				LoginDialog(playerid);
				return 1;
			}

			// %e -  Kisz�ri az adatot, SQL injection elker�l�se v�gett. B�vebben itt olvashatsz r�la: http://sampforum.hu/index.php?topic=9285.0
			mysql_format(1, g_szQuery, sizeof(g_szQuery), "SELECT * FROM `players` WHERE `name` = '%s' AND `pass` COLLATE `utf8_bin` LIKE '%e'", pName(playerid), inputtext);
			mysql_pquery(1, g_szQuery, "THREAD_DialogLogin", "dd", playerid, g_pQueryQueue[playerid]);
		}
		case DIALOG_REGISTER:
		{
			if(!response)
				return RegisterDialog(playerid);

			if(isnull(inputtext))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem �rt�l be semilyen jelsz�t!");
				RegisterDialog(playerid);
				return 1;
			}

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Rossz jelsz� hossz�s�g! 3 - 20");
				RegisterDialog(playerid);
				return 1;
			}

			format(g_szQuery, sizeof(g_szQuery), "SELECT `reg_id` FROM `players` WHERE `name` = '%s'", pName(playerid));
			mysql_pquery(1, g_szQuery, "THREAD_Register_1", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
		case DIALOG_CHANGENAME:
		{
			if(!response)
				return 0;

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem megfelel� hossz� a neved! 3 �s 20 karakter k�z�tt legyen!");

				ChangeNameDialog(playerid);
				return 1;
			}

			if(!NameCheck(inputtext))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem megfelel� n�v! Csak ezek a karakterek lehetnek benne: {" #XCOLOR_GREEN "}A-Z, 0-9, [], (), $, @. {" #XCOLOR_RED "}Ezenk�v�l helyet nem tartamlazhat!");

				ChangeNameDialog(playerid);
				return 1;
			}

			if(!strcmp(inputtext, pName(playerid), true))
			{
				SendClientMessage(playerid, COLOR_RED, "Jelenleg is ez a neved! �rj be egy m�sikat!");

				ChangeNameDialog(playerid);
				return 1;
			}

			mysql_format(1, g_szQuery, sizeof(g_szQuery), "SELECT `reg_id` FROM `players` WHERE `name` = '%e'", inputtext);
			mysql_pquery(1, g_szQuery, "THREAD_Changename", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
		case DIALOG_CHANGEPASS:
		{
			if(!response)
				return 0;

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem megfelel� hossz� a jelszavad! 3 �s 20 karakter k�z�tt legyen!");

				ShowPlayerDialog(playerid, DIALOG_CHANGEPASS, DIALOG_STYLE_INPUT, "Jelsz�v�lt�s", "Lentre �rd be az �j jelszavad! \n\n", "V�ltoztat�s", "M�gse");
				return 1;
			}

			format(g_szQuery, sizeof(g_szQuery), "SELECT `pass` FROM `players` WHERE `reg_id` = %d", GetPVarInt(playerid, "RegID"));
			mysql_pquery(1, g_szQuery, "THREAD_Changepass", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
		case DIALOG_FINDPLAYER:
		{
			if(!response)
				return 0;

			format(g_szQuery, sizeof(g_szQuery), "SELECT * FROM `players` WHERE `name` = '%s'", inputtext);
			mysql_pquery(1, g_szQuery, "THREAD_Findplayer", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
	}
	return 1;
}

forward THREAD_DialogLogin(playerid, queue);
public THREAD_DialogLogin(playerid, queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_DialogLogin);

	new
	    rows,
	    fields;
	cache_get_data(rows, fields);
	if(rows != 1)
	{
		SendClientMessage(playerid, COLOR_RED, "HIBA: Rossz jelsz�.");
		LoginDialog(playerid);
		return 1;
	}

	LoginPlayer(playerid);
	GetPlayerIp(playerid, g_szIP, sizeof(g_szIP));

	format(g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `ip` = '%s' WHERE `reg_id` = %d", g_szIP, GetPVarInt(playerid, "RegID"));
	mysql_pquery(1, g_szQuery);

	SendClientMessage(playerid, COLOR_GREEN, !"Sikersen bejelentkezt�l!");
	return 1;
}

forward THREAD_Register_1(playerid, password[], queue);
public THREAD_Register_1(playerid, password[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Register_1);

	new
	    rows,
	    fields;
	cache_get_data(rows, fields);
	if(rows)
	{
		SendClientMessage(playerid, COLOR_RED, "MySQL sorok sz�ma nem 0, valami hiba t�rt�nt a kiv�laszt�s k�zben!");
		SendClientMessage(playerid, COLOR_RED, "Ezt a hib�t jelezd a tulajdonosnak! Kickelve lett�l, mert ebb�l hiba keletkezhet!");

		printf("MySQL rosw > 1 (%d, %s)", playerid, password);
		Kick(playerid);
		return 1;
	}

	getdate(year, month, day);
	gettime(hour, minute, second);

	GetPlayerIp(playerid, g_szIP, sizeof(g_szIP));

	mysql_format(1, g_szQuery, sizeof(g_szQuery), "INSERT INTO `players`(reg_id, name, ip, pass, reg_date, laston) VALUES(0, '%s', '%s', '%e', '%02d.%02d.%02d/%02d.%02d.%02d', '%02d.%02d.%02d/%02d.%02d.%02d')", pName(playerid), g_szIP, password, year, month, day, hour, minute, second, year, month, day, hour, minute, second);
	mysql_pquery(1, g_szQuery, "THREAD_Register_2", "dsd", playerid, password, g_pQueryQueue[playerid]);
	return 1;
}

forward THREAD_Register_2(playerid, password[], queue);
public THREAD_Register_2(playerid, password[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Register_2);

	new
		iRegID = cache_insert_id();
	SetPVarInt(playerid, "RegID", iRegID); // J�t�kos Regisztr�ci�s ID-j�t be�ll�tuk arra, amelyik sorba �rtunk el�bb ( INSERT INTO )
	SetPVarInt(playerid, "Style", 4);
	g_PlayerFlags{playerid} |= e_LOGGED_IN;

	SendClientMessagef(playerid, COLOR_GREEN, "Sikeresen regisztr�lt�l! A jelszavad: {" #XCOLOR_RED "}%s. {" #XCOLOR_GREEN "}Felhaszn�l� ID: {" #XCOLOR_BLUE "}%d", password, iRegID);
	SendClientMessage(playerid, COLOR_PINK, "Ennyi lenne a MySQL regiszt�ci� {" #XCOLOR_BLUE "}:)");
	return 1;
}

forward THREAD_Changename(playerid, inputtext[], queue);
public THREAD_Changename(playerid, inputtext[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Changename);

	new
	    rows,
	    fields;
	cache_get_data(rows, fields);
	if(rows)
	{
		SendClientMessage(playerid, COLOR_RED, "HIBA: Ez a n�v m�r haszn�latban van!");
		SendClientMessage(playerid, COLOR_GREEN, "�rj be egy m�s nevet, vagy menj a 'M�gse' gombra!");

		ChangeNameDialog(playerid);
		return 1;
	}

	new
		szOldName[MAX_PLAYER_NAME + 1],
		pRegID = GetPVarInt(playerid, "RegID");
	GetPlayerName(playerid, szOldName, sizeof(szOldName));

	if(SetPlayerName(playerid, inputtext) != 1)
	{
		SendClientMessage(playerid, COLOR_RED, "Nem megfelel� n�v! �rj be egy m�sikat!");

		ChangeNameDialog(playerid);
		return 1;
	}

	getdate(year, month, day);
	gettime(hour, minute, second);

	format(g_szQuery, sizeof(g_szQuery), "INSERT INTO `namechanges`(id, reg_id, oldname, newname, time) VALUES(0, %d, '%s', '%s', '%02d.%02d.%02d/%02d.%02d.%02d')", pRegID, szOldName, inputtext, year, month, day, hour, minute, second);
	mysql_pquery(1, g_szQuery);

	format(g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `name` = '%s' WHERE `reg_id` = %d", inputtext, pRegID);
	mysql_pquery(1, g_szQuery);

	SendClientMessagef(playerid, COLOR_YELLOW, "Sikeresen �tv�ltottad a neved! �j neved: {" #XCOLOR_WHITE "}%s.", inputtext);
	return 1;
}

forward THREAD_Changepass(playerid, password[], queue);
public THREAD_Changepass(playerid, password[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Changepass);

	new
	    szOldPass[21],
	    szEscaped[21],
	    pRegID = GetPVarInt(playerid, "RegID");
	cache_get_row(0, 0, szOldPass);

	format(g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `pass` = '%e' WHERE `reg_id` = %d", password, pRegID);
	mysql_pquery(1, g_szQuery);

	getdate(year, month, day);
	gettime(hour, minute, second);

	format(g_szQuery, sizeof(g_szQuery), "INSERT INTO `namechanges_p`(id, reg_id, name, oldpass, newpass, time) VALUES(0, %d, '%s', '%s', '%s', '%02d.%02d.%02d/%02d.%02d.%02d')", pRegID, pName(playerid), szOldPass, szEscaped, year, month, day, hour, minute, second);
	mysql_pquery(1, g_szQuery);

	SendClientMessagef(playerid, COLOR_YELLOW, "Sikeresen �t�ll�totad a jelszavad! �j jelszavad: {" #XCOLOR_GREEN "}%s", password);
	return 1;
}

forward THREAD_Findplayer(playerid, inputtext[], queue);
public THREAD_Findplayer(playerid, inputtext[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Findplayer);

	new
		szFetch[12],
		szRegDate[24],
		szLaston[24],
		iData[6];
	iData[0] = cache_get_row_int(0, 0); // regid
	cache_get_row(0, 4, szRegDate);
	cache_get_row(0, 5, szLaston);
	iData[1] = cache_get_row_int(0, 6);// money
	iData[2] = cache_get_row_int(0, 7); // score
	iData[3] = cache_get_row_int(0, 8); // kills
	iData[4] = cache_get_row_int(0, 9); // deaths
	iData[5] = cache_get_row_int(0, 10); // style

	switch(iData[5])
	{
		case FIGHT_STYLE_NORMAL: szFetch = "Norm�l";
	   	case FIGHT_STYLE_BOXING: szFetch = "Boxol�";
	   	case FIGHT_STYLE_KUNGFU: szFetch = "Kungfu";
		case FIGHT_STYLE_KNEEHEAD: szFetch = "Kneehead";
		case FIGHT_STYLE_GRABKICK: szFetch = "Grabkick";
		case FIGHT_STYLE_ELBOW: szFetch = "Elbow";
	}

	// �zenet elk�ld�se
	SendClientMessagef(playerid, COLOR_RED, "N�v: %s, ID: %d, RegID: %d, P�nz: %d, Pont: %d", inputtext, playerid, iData[0], iData[1], iData[2]);
	SendClientMessagef(playerid, COLOR_YELLOW, "�l�sek: %d, Hal�lok: %d, Ar�ny: %.2f, �t�s St�lus: %s", iData[3], iData[4], (iData[3] && iData[4]) ? (floatdiv(iData[3], iData[4])) : (0.0), szFetch);
	SendClientMessagef(playerid, COLOR_GREEN, "Regiszt�ci� ideje: {" #XCOLOR_BLUE "}%s{" #XCOLOR_GREEN "}, Utulj�ra a szerveren: {" #XCOLOR_BLUE "}%s", szRegDate, szLaston);
	return 1;
}

public OnPlayerDeath(playerid, killerid, reason)
{
	if(IsPlayerConnected(killerid) && killerid != INVALID_PLAYER_ID)
	{
		SetPVarInt(killerid, "Kills", GetPVarInt(killerid, "Kills") + 1);
	}

	SetPVarInt(playerid, "Deaths", GetPVarInt(playerid, "Deaths") + 1);
	return 1;
}

// Statisztika felmutat�
CMD:stats(playerid, params[])
{
	format(g_szQuery, sizeof(g_szQuery), "SELECT `reg_date`, `laston` FROM `players` WHERE `reg_id` = %d", GetPVarInt(playerid, "RegID")); // Kiv�lasztjuk a reg_date �s a laston mez�t
	mysql_pquery(1, g_szQuery, "THREAD_Stats", "dd", playerid, g_pQueryQueue[playerid]);
	return 1;
}

forward THREAD_Stats(playerid, queue);
public THREAD_Stats(playerid, queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Stats);

	new
		RegDate[24],
		Laston[24],
		szStyle[24],
		Kills = GetPVarInt(playerid, "Kills"),
		Deaths = GetPVarInt(playerid, "Deaths");
	cache_get_row(0, 0, RegDate);
	cache_get_row(0, 1, Laston);

	switch(GetPlayerFightingStyle(playerid))
	{
		case FIGHT_STYLE_NORMAL: szStyle = "Norm�l";
	   	case FIGHT_STYLE_BOXING: szStyle = "Boxol�";
	   	case FIGHT_STYLE_KUNGFU: szStyle = "Kungfu";
		case FIGHT_STYLE_KNEEHEAD: szStyle = "Kneehead";
		case FIGHT_STYLE_GRABKICK: szStyle = "Grabkick";
		case FIGHT_STYLE_ELBOW: szStyle = "Elbow";
	}

	// �zenet elk�ld�se
	SendClientMessagef(playerid, COLOR_RED, "N�v: %s, ID: %d, RegID: %d, P�nz: %d, Pont: %d", pName(playerid), playerid, GetPVarInt(playerid, "RegID"), GetPlayerMoney(playerid), GetPlayerScore(playerid));
	SendClientMessagef(playerid, COLOR_YELLOW, "�l�sek: %d, Hal�lok: %d, Ar�ny: %.2f, �t�s St�lus: %s", Kills, Deaths, (Kills && Deaths) ? (floatdiv(Kills, Deaths)) : (0.0), szStyle);
	SendClientMessagef(playerid, COLOR_GREEN, "Regiszt�ci� ideje: {" #XCOLOR_BLUE "}%s{" #XCOLOR_GREEN "}, Utulj�ra a szerveren: {" #XCOLOR_BLUE "}%s", RegDate, Laston);
	return 1;
}
/*
CMD:kill(playerid, params[])
{
	SetPlayerHealth(playerid, 0.0);
	return 1;
}

CMD:flag(playerid, params[])
{
	SendClientMessagef(playerid, -1, "Logged: %d, FirstSpawn: %d", g_PlayerFlags{playerid} & e_LOGGED_IN, g_PlayerFlags{playerid} & e_FIRST_SPAWN);
	return 1;
}
*/
CMD:changename(playerid, params[])
{
	ChangeNameDialog(playerid);
	return 1;
}

CMD:changepass(playerid, params[])
{
	ShowPlayerDialog(playerid, DIALOG_CHANGEPASS, DIALOG_STYLE_PASSWORD, "Jelsz�v�lt�s", "Lentre �rd be az �j jelszavad! \n\n", "V�ltoztat�s", "M�gse");
	return 1;
}

CMD:findplayer(playerid, params[])
{
	if(isnull(params)) return SendClientMessage(playerid, COLOR_RED, "HASZN�LAT: /findplayer <J�t�kos N�vr�szlet>");
	if(strlen(params) > MAX_PLAYER_NAME) return SendClientMessage(playerid, COLOR_RED, "HIBA: T�l hossz� a r�szlet, maximum 24 karakter lehet!");

	format(g_szQuery, sizeof(g_szQuery), "SELECT `name` FROM `players` WHERE `name` LIKE '%s%s%s'", "%%", params, "%%");
	mysql_pquery(1, g_szQuery, "THREAD_FindplayerDialog", "dsd", playerid, params, g_pQueryQueue[playerid]);
	return 1;
}

forward THREAD_FindplayerDialog(playerid, reszlet[], queue);
public THREAD_FindplayerDialog(playerid, reszlet[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_FindplayerDialog);

	new
	    rows,
	    fields;
	cache_get_data(rows, fields);

	if(!rows)
	{
		SendClientMessagef(playerid, COLOR_RED, "Nincs tal�lat a(z) '%s' r�szletre!", reszlet);
		return 1;
	}
	else if(rows > 180)
	{
		SendClientMessagef(playerid, COLOR_RED, "A(z) '%s' r�szletre t�bb, mint 180 tal�lad van! < %d >!", reszlet, rows);
		return 1;
	}

	new
	    x,
	    szName[MAX_PLAYER_NAME],
	    str[64];
	g_szDialogFormat[0] = EOS;
	for( ; x != rows; x++)
	{
		cache_get_row(x, 0, szName);
		strcat(g_szDialogFormat, szName);
		strcat(g_szDialogFormat, "\n");
	}

	format(str, sizeof(str), "Tal�latok a(z) '%s' r�szletre.. (%d)", reszlet, x);
	ShowPlayerDialog(playerid, DIALOG_FINDPLAYER, DIALOG_STYLE_LIST, str, g_szDialogFormat, "Megtekint", "M�gse");
	return 1;
}

/////////////////////////////////////////
stock LoginDialog(playerid)
{
	new
	    str[64];
	format(str, sizeof(str), "{" #XCOLOR_WHITE "}Bejelentkez�s: {%06x}%s(%d)", GetPlayerColor(playerid) >>> 8, pName(playerid), playerid);
	ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, str, !"{" #XCOLOR_GREEN "}�dv�z�llek a \n\n{" #XCOLOR_BLUE "}My{" #XCOLOR_YELLOW "}SQL {" #XCOLOR_GREEN "}teszt szerveren! \n\nTe m�r regiszt�lva vagy. Lentre �rd be a jelszavad", !"Bejelentkez�s", !"M�gse");
	return 1;
}

stock RegisterDialog(playerid)
{
	new
	    str[64];
	format(str, sizeof(str), "{" #XCOLOR_WHITE "}Regisztr�ci�: {%06x}%s(%d)", GetPlayerColor(playerid) >>> 8, pName(playerid), playerid);

	#if defined NINCS_REG_CSILLAG
		ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_INPUT, str, !"{" #XCOLOR_GREEN "}�dv�z�llek a \n\n{" #XCOLOR_BLUE "}My{" #XCOLOR_YELLOW "}SQL {" #XCOLOR_GREEN "}teszt szerveren! \n\nItt m�g nem regisztr�lt�l. Lentre �rd be a jelszavad", !"Regiszt�ci�", !"M�gse");
	#else
		ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, str, !"{" #XCOLOR_GREEN "}�dv�z�llek a \n\n{" #XCOLOR_BLUE "}My{" #XCOLOR_YELLOW "}SQL {" #XCOLOR_GREEN "}teszt szerveren! \n\nItt m�g nem regisztr�lt�l. Lentre �rd be a jelszavad", !"Regiszt�ci�", !"M�gse");
	#endif
	return 1;
}

/* Bejelentkez�s */
stock LoginPlayer(playerid)
{
	new
		iPVarSet[6],
		iRegID = GetPVarInt(playerid, "LineID");
	// Ha a line ID 0, teh�t a MySQL nem adott vissza sorokat, akkor semmik�pp sem jelentkezhez be!
	// Ennek nem szabadna el�fordulnia, de biztons�g kedv��rt teszek r� v�delmet.
	if(!iRegID) return printf("HIBA: Rossz reg ID! J�t�kos: %s(%d) (regid: %d)", pName(playerid), playerid, iRegID);
    
	SetPVarInt(playerid, "RegID", iRegID); // RegID-t be�ll�tjuk
	iPVarSet[0] = cache_get_row_int(0, 0);  // RegID
	iPVarSet[1] = cache_get_row_int(0, 6); // Money
	iPVarSet[2] = cache_get_row_int(0, 7); // Score
	iPVarSet[3] = cache_get_row_int(0, 8); // Kills
	iPVarSet[4] = cache_get_row_int(0, 9); // Deaths
	iPVarSet[5] = cache_get_row_int(0, 10); // Fightingstyle

	SetPVarInt(playerid, "Cash", iPVarSet[1]); // A p�nz�t egy PVar-ban t�roljuk, mert a skinv�laszt�sn�l nemlehet a j�t�kos p�nz�t �ll�tani.
	SetPlayerScore(playerid, iPVarSet[2]);

	SetPVarInt(playerid, "Kills", iPVarSet[3]);
	SetPVarInt(playerid, "Deaths", iPVarSet[4]);
	SetPVarInt(playerid, "Style", iPVarSet[5]);

	g_PlayerFlags{playerid} |= e_LOGGED_IN;
	return 1;
}

stock SavePlayer(playerid, regid)
{
	if(IsPlayerNPC(playerid)) return 1;

	// Ha nincs bejelentkezve �s m�g nem spawnolt le, akkor nem mentj�k. Ezt aj�nlatos itthagyni, mivel ezmiatt nekem sok bug keletkezett!
	if(g_PlayerFlags{playerid} & (e_LOGGED_IN | e_FIRST_SPAWN) == (e_LOGGED_IN | e_FIRST_SPAWN))
	{
		getdate(year, month, day);
		gettime(hour, minute, second);

		format(g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `laston` = '%02d.%02d.%02d/%02d.%02d.%02d', `money` = %d, `score` = %d, `kills` = %d, `deaths` = %d, `fightingstyle` = '%d' WHERE `reg_id` = %d",
		year, month, day, hour, minute, second, GetPlayerMoney(playerid), GetPlayerScore(playerid), GetPVarInt(playerid, "Kills"), GetPVarInt(playerid, "Deaths"), GetPlayerFightingStyle(playerid),
		regid);

		mysql_pquery(1, g_szQuery);
		// %02d azt jelenti, hogyha a sz�m egyjegy� (1, 5, 7, stb... ), akkor tegyen el� egy 0-t. Pl: 05, 07.
		// Ezt �ltal�ban id�re haszn�lj�k, mivel �gy '�rthet�bb'.
		// Ez ugyan�gy m�k�dik %03d-vel %04d-vel, �s �gy tov�b... ^
	}
	return 1;
}

stock pName(playerid)
{
	static // "Helyi" glob�lis v�ltoz�
		s_szName[MAX_PLAYER_NAME];
	GetPlayerName(playerid, s_szName, sizeof(s_szName));
	return s_szName;
}

/* SQL T�bla */
/*
CREATE TABLE IF NOT EXISTS `connections` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(21) NOT NULL,
  `ip` varchar(16) NOT NULL,
  `serial` varchar(128) NOT NULL,
  `time` varchar(24) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `namechanges` (
  `id` smallint(5) NOT NULL AUTO_INCREMENT,
  `reg_id` mediumint(8) NOT NULL,
  `oldname` varchar(21) NOT NULL,
  `newname` varchar(21) NOT NULL,
  `time` varchar(24) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `reg_id` (`reg_id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `namechanges_p` (
  `id` smallint(5) NOT NULL AUTO_INCREMENT,
  `reg_id` mediumint(8) NOT NULL,
  `name` varchar(24) NOT NULL,
  `oldpass` varchar(21) NOT NULL,
  `newpass` varchar(21) NOT NULL,
  `time` varchar(24) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `reg_id` (`reg_id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `players` (
  `reg_id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(24) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `ip` varchar(20) NOT NULL,
  `pass` varchar(20) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `reg_date` varchar(24) NOT NULL,
  `laston` varchar(24) NOT NULL,
  `money` int(11) NOT NULL DEFAULT '0',
  `score` int(11) NOT NULL DEFAULT '0',
  `kills` mediumint(11) unsigned NOT NULL DEFAULT '0',
  `deaths` mediumint(11) unsigned NOT NULL DEFAULT '0',
  `fightingstyle` enum('4','5','6','7','15','16') NOT NULL DEFAULT '4',
  PRIMARY KEY (`reg_id`),
  KEY `name` (`name`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;
*/
