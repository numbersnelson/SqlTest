USE [UC_POLog]
GO
/****** Object:  StoredProcedure [dbo].[csp.POLog.Invoice.Export.Batch.Create]    Script Date: 07/23/2012 12:23:51 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






/*

	CREATED BY: Uttam
	CREATED ON: Dec 9, 2010
	DEPENDENT OBJECTS: 
	OBJECTIVE: 
		-Creates batch 

	TEST:
	
		declare @ExportBatchID int
		declare @ReturnMsg varchar(1000)
		
		exec [dbo].[csp.POLog.Invoice.Export.Batch.Create]
			 @TeamCode='',
			 @AddedByDNNUserID=11,
			 @ExportBatchID = @ExportBatchID OUT,
			 @ReturnMsg = @ReturnMsg OUT
			 
		select @ExportBatchID, @ReturnMsg
		
		
		

*/

ALTER PROCEDURE [dbo].[csp.POLog.Invoice.Export.Batch.Create]
	@TeamCode VARCHAR(20)
	, @AddedByDNNUserID INT
	, @ExportBatchID INT OUT
	, @ReturnMsg VARCHAR(1000) OUT
	, @SourceType VARCHAR(20) = ''
	, @ReturnMsgType VARCHAR(20) = '' OUT
	, @GroupList varchar(8000)
AS

DECLARE @AddedByUserID INT
		, @TeamID INT



SET @ReturnMsg  = ''
SET @ReturnMsgType = ''
SET @TeamID = 0 --select all districts


SELECT @AddedByUserID = dbo.GetRoutingUserID(@AddedByDNNUserID)
IF @TeamCode <> '-1' AND @TeamCode <> ''
BEGIN
	SELECT @TeamID = TeamID FROM RoutingDB.dbo.ctbl_Team WITH(NOLOCK) WHERE TeamCode = @TeamCode
END


-- Get Districts to which User has access rights
CREATE TABLE #tmpUserTeam(TeamID INT,TeamCode VARCHAR(20))

INSERT INTO #tmpUserTeam (TeamID,TeamCode)
SELECT
	distinct ut.TeamID,t.TeamCode 
FROM
	[RoutingDb].[dbo].ctbl_UserTeamDerived ut WITH(NOLOCK)
INNER JOIN 
	RoutingDB.dbo.ctbl_Team t WITH(NOLOCK) 
	on t.TeamID = ut.TeamID
WHERE
	UserID = @AddedByUserID
	AND 
	TeamHierarchyID = 1



--validation starts

IF @GroupList = '' 
BEGIN
	IF @TeamCode <> '-1' AND @TeamID IS NULL
	BEGIN
		SET @ReturnMsg = 'District does not exist.<br/>'
	END
END
ELSE
BEGIN
	IF @TeamCode = ''
		SET @TeamID = -1
END


IF EXISTS(SELECT ExportBatchID FROM dbo.[ctbl.Invoice.Export.Batch] WITH(NOLOCK) WHERE ExportedDate IS NULL)
BEGIN
	SET @ReturnMsg = @ReturnMsg + 'There is already a batch which is not exported.<br/>'
END


IF @ReturnMsg <> ''
BEGIN
	SET @ReturnMsgType = 'ERROR'
	RETURN
END	

--validation ends



create table #tmpGroupDistricts
(
	SegmentValue varchar(50)
)

INSERT INTO #tmpGroupDistricts
	EXEC [dbo].[csp.UC_Targets.cust.Group.GetGroupItems]  @GroupList = @GroupList

alter table #tmpGroupDistricts add DistrictID int

update gd
	set gd.DistrictID = tm.TeamID
from
	#tmpGroupDistricts gd
inner join
	RoutingDb.dbo.ctbl_Team tm
	on gd.SegmentValue = tm.TeamCode










SET XACT_ABORT ON
BEGIN TRAN

	INSERT INTO dbo.[ctbl.Invoice.Export.Batch] 
	(
		AddedByUserID
		, AddedDate
		, BatchStatusCode
		, IsCompleted
		, SourceType
	)
	VALUES
	(
		 @AddedByUserID
		, GETUTCDATE()
		, 'Created'
		, 0
		, @SourceType
	)

	SET @ExportBatchID = SCOPE_IDENTITY()
		
	--save into batch details
	IF @SourceType = 'Invoice'
	BEGIN
	
		DECLARE @PcardVendorID INT
		SELECT @PcardVendorID = VendorID FROM UC_DMS.dbo.[ctbl.Vendor] WHERE VendorCode = 'PCARD'
		
		--remove districts which do not have export data
		DELETE FROM #tmpGroupDistricts 
		WHERE 
			DistrictID 
		NOT IN
		(
			SELECT 
				it.RoutingDistrictID
			FROM
				dbo.[ctbl.Invoice.Tranx] it WITH(NOLOCK)
			INNER JOIN 
				RoutingDB.dbo.[ctbl_Team] t WITH(NOLOCK)
				ON t.TeamCode = it.ClassCode
			INNER JOIN
				dbo.[ctbl.Invoice.Export.FirstExportTranx] ie WITH(NOLOCK)
				ON  it.InvoiceTranxID >= ie.FirstExportInvoiceTranxId AND t.TeamID = ie.BusUnitId
			WHERE
				it.IsApproved = 1
				AND
				it.ExportedDate IS NULL
				AND 
				ISNULL(it.IsDeleted, 0) = 0
				AND
				it.InvoiceTranxTypeID = 1
				AND
				(it.VendorID <> @PcardVendorID OR @PcardVendorID IS NULL)
				AND 
				it.NetInvoiceAmount >= 0 


		)
		
		--include district selected in district dropdown list to 
		--temporary table if district is selected and there is nothing in District Gruoupings
		if @TeamID <> 0 and @TeamID <> -1
			insert into #tmpGroupDistricts (DistrictID) values(@TeamID)
		
		INSERT INTO dbo.[ctbl.Invoice.Export.Batch.Detail]
		(
			InvoiceTranxID
			, ExportBatchID
			, ExportStatusCode
			, IsExported
		)
		SELECT 
			it.InvoiceTranxID
			, @ExportBatchID
			, 'Created'
			,0
		FROM
			dbo.[ctbl.Invoice.Tranx] it WITH(NOLOCK)
		INNER JOIN 
			RoutingDB.dbo.[ctbl_Team] t WITH(NOLOCK)
			ON t.TeamCode = it.ClassCode
		INNER JOIN
			dbo.[ctbl.Invoice.Export.FirstExportTranx] ie WITH(NOLOCK)
			ON  it.InvoiceTranxID >= ie.FirstExportInvoiceTranxId AND t.TeamID = ie.BusUnitId
		INNER JOIN #tmpUserTeam tmp
			ON tmp.TeamID = it.RoutingDistrictID
		WHERE
			it.IsApproved = 1
			AND
			it.ExportedDate IS NULL
			--AND
			--(it.RoutingDistrictID = @TeamID OR @TeamID = 0)
			AND
			(@TeamID = 0 OR it.RoutingDistrictID IN (SELECT tgd.DistrictID FROM #tmpGroupDistricts tgd INNER JOIN #tmpUserTeam tmp ON tmp.TeamID = tgd.DistrictID )) 
			AND 
			ISNULL(it.IsDeleted, 0) = 0
			AND
			it.InvoiceTranxTypeID = 1
			AND
			(it.VendorID <> @PcardVendorID OR @PcardVendorID IS NULL)
			AND 
			it.NetInvoiceAmount >= 0 




	END


			
	IF @SourceType = 'ExpReport'
	BEGIN
		--remove districts which do not have export data
		DELETE FROM #tmpGroupDistricts 
		WHERE 
			DistrictID 
		NOT IN
		(
			SELECT 
				it.RoutingDistrictID
			FROM
				UC_MiscDoc.dbo.[ctbl.Invoice.Tranx] it WITH(NOLOCK)
			WHERE
				it.IsApproved = 1
				AND
				it.ExportedDate IS NULL
				AND 
				ISNULL(it.IsDeleted, 0) = 0
		)
		
		--include district selected in district dropdown list to 
		--temporary table if district is selected and there is nothing in District Gruoupings
		if @TeamID <> 0 and @TeamID <> -1
			insert into #tmpGroupDistricts (DistrictID) values(@TeamID)
		

		INSERT INTO dbo.[ctbl.Invoice.Export.Batch.Detail]
		(
			InvoiceTranxID
			, ExportBatchID
			, ExportStatusCode
			, IsExported
		)
		SELECT 
			it.InvoiceTranxID
			, @ExportBatchID
			, 'Created'
			,0
		FROM
			UC_MiscDoc.dbo.[ctbl.Invoice.Tranx] it WITH(NOLOCK)
		INNER JOIN #tmpUserTeam tmp
			ON tmp.TeamID = it.RoutingDistrictID
		WHERE
			it.IsApproved = 1
			AND
			it.ExportedDate IS NULL
			--AND
			--(it.RoutingDistrictID = @TeamID OR @TeamID = 0)
			AND
			(@TeamID = 0 OR it.RoutingDistrictID IN (SELECT tgd.DistrictID FROM #tmpGroupDistricts tgd INNER JOIN #tmpUserTeam tmp ON tmp.TeamID = tgd.DistrictID )) 
			AND 
			ISNULL(it.IsDeleted, 0) = 0


	END


























	















	SELECT
		COUNT(ExportBatchID) AS CurrentBatchCount
	FROM
		dbo.[ctbl.Invoice.Export.Batch.Detail] WITH(NOLOCK)
	WHERE
		ExportBatchID = @ExportBatchID
	
	
	SELECT
		SourceType
	FROM
		dbo.[ctbl.Invoice.Export.Batch] WITH(NOLOCK)
	WHERE
		ExportBatchID = @ExportBatchID
		
SET @ReturnMsgType = 'MESSAGE'
SET @ReturnMsg = 'Batch Created Successfully.'

COMMIT TRAN 










